-- Create enum for system status
CREATE TYPE system_status_type AS ENUM ('initialized', 'reset', 'backup', 'restore', 'error');

-- Create system_status table for tracking database state
CREATE TABLE IF NOT EXISTS system_status (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    status system_status_type NOT NULL DEFAULT 'initialized',
    last_known_state jsonb NOT NULL DEFAULT '{}'::jsonb,
    last_reset_time timestamptz,
    last_backup_time timestamptz,
    last_restore_time timestamptz,
    error_count integer DEFAULT 0,
    last_error jsonb,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL
);

-- Create function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create trigger for updated_at
CREATE TRIGGER update_system_status_updated_at
    BEFORE UPDATE ON system_status
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Create function to log system events
CREATE OR REPLACE FUNCTION log_system_event(
    p_status system_status_type,
    p_state jsonb DEFAULT NULL,
    p_error jsonb DEFAULT NULL
) RETURNS uuid AS $$
DECLARE
    v_id uuid;
BEGIN
    INSERT INTO system_status (
        status,
        last_known_state,
        last_reset_time,
        last_backup_time,
        last_restore_time,
        error_count,
        last_error
    )
    VALUES (
        p_status,
        COALESCE(p_state, '{}'::jsonb),
        CASE WHEN p_status = 'reset' THEN now() ELSE NULL END,
        CASE WHEN p_status = 'backup' THEN now() ELSE NULL END,
        CASE WHEN p_status = 'restore' THEN now() ELSE NULL END,
        CASE WHEN p_status = 'error' THEN 1 ELSE 0 END,
        p_error
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create function to update error count
CREATE OR REPLACE FUNCTION increment_error_count() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'error' THEN
        NEW.error_count := COALESCE(OLD.error_count, 0) + 1;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for error counting
CREATE TRIGGER count_errors
    BEFORE INSERT OR UPDATE ON system_status
    FOR EACH ROW
    EXECUTE FUNCTION increment_error_count();

-- Insert initial system status
SELECT log_system_event(
    'initialized',
    jsonb_build_object(
        'message', 'System initialized',
        'timestamp', CURRENT_TIMESTAMP,
        'version', '1.0.0'
    )
);

-- Grant permissions
GRANT ALL ON TABLE system_status TO postgres, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION log_system_event TO postgres, anon, authenticated, service_role;

-- Create indexes
CREATE INDEX idx_system_status_status ON system_status(status);
CREATE INDEX idx_system_status_created_at ON system_status(created_at);
CREATE INDEX idx_system_status_error_count ON system_status(error_count) WHERE status = 'error';

-- Add token usage tracking table
CREATE TABLE public.token_usage (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL,
    content_id uuid NOT NULL,
    input_tokens integer NOT NULL DEFAULT 0,
    output_tokens integer NOT NULL DEFAULT 0,
    total_tokens integer NOT NULL DEFAULT 0,
    credits_used integer NOT NULL DEFAULT 1,
    created_at timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT fk_user FOREIGN KEY (user_id) 
        REFERENCES auth.users(id) 
        ON DELETE CASCADE 
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT fk_content FOREIGN KEY (content_id) 
        REFERENCES public.content(id) 
        ON DELETE CASCADE 
        DEFERRABLE INITIALLY DEFERRED
);

-- Create index for better performance
CREATE INDEX idx_token_usage_user_id ON public.token_usage(user_id);
CREATE INDEX idx_token_usage_content_id ON public.token_usage(content_id);

-- Add trigger for token_usage updated_at
CREATE TRIGGER update_token_usage_updated_at
    BEFORE UPDATE ON public.token_usage
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Grant privileges
GRANT ALL ON TABLE public.token_usage TO service_role;

-- Enable RLS
ALTER TABLE public.token_usage ENABLE ROW LEVEL SECURITY;

-- Create policies for token_usage
CREATE POLICY "Users can view their own token usage"
    ON public.token_usage FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Super admins can view all token usage"
    ON public.token_usage FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles
            WHERE auth_id = auth.uid()
            AND role = 'super_admin'
        )
    );

CREATE POLICY "School admins can view their school users' token usage"
    ON public.token_usage FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.school_users su
            JOIN public.user_profiles up ON up.id = su.user_id
            JOIN public.user_profiles tu_up ON tu_up.auth_id = token_usage.user_id
            WHERE up.auth_id = auth.uid()
            AND su.role = 'admin'
            AND su.school_id = (
                SELECT su2.school_id 
                FROM public.school_users su2 
                JOIN public.user_profiles up2 ON up2.id = su2.user_id 
                WHERE up2.auth_id = token_usage.user_id
                LIMIT 1
            )
        )
    );

-- Extend schools table with additional fields
ALTER TABLE public.schools 
ADD COLUMN address_line1 text,
ADD COLUMN address_line2 text,
ADD COLUMN city text,
ADD COLUMN state text,
ADD COLUMN pin_code text,
ADD COLUMN country text DEFAULT 'India',
ADD COLUMN principal_name text,
ADD COLUMN principal_email text,
ADD COLUMN principal_phone text,
ADD COLUMN assistant_name text,
ADD COLUMN assistant_email text,
ADD COLUMN assistant_mobile text,
ADD COLUMN assistant_landline text;

-- Add user_type to user_profiles
ALTER TABLE public.user_profiles
ADD COLUMN user_type text CHECK (user_type IN ('individual', 'school_user', 'school_admin', 'super_admin'));

-- Create a view for aggregated token usage
CREATE OR REPLACE VIEW public.user_token_usage AS
SELECT 
    u.auth_id,
    u.id as user_profile_id,
    u.email,
    u.first_name,
    u.last_name,
    COALESCE(s.id, NULL) as school_id,
    COALESCE(s.name, 'Individual') as school_name,
    COUNT(DISTINCT t.content_id) as documents_generated,
    SUM(t.input_tokens) as total_input_tokens,
    SUM(t.output_tokens) as total_output_tokens,
    SUM(t.total_tokens) as total_tokens,
    SUM(t.credits_used) as total_credits_used
FROM 
    public.user_profiles u
LEFT JOIN 
    public.school_users su ON u.id = su.user_id
LEFT JOIN 
    public.schools s ON su.school_id = s.id
LEFT JOIN 
    public.token_usage t ON u.auth_id = t.user_id
GROUP BY 
    u.auth_id, u.id, u.email, u.first_name, u.last_name, s.id, s.name;

-- Create a view for school usage
CREATE OR REPLACE VIEW public.school_token_usage AS
SELECT 
    s.id as school_id,
    s.name as school_name,
    COUNT(DISTINCT u.auth_id) as active_users,
    COUNT(DISTINCT t.content_id) as documents_generated,
    SUM(t.input_tokens) as total_input_tokens,
    SUM(t.output_tokens) as total_output_tokens,
    SUM(t.total_tokens) as total_tokens,
    SUM(t.credits_used) as total_credits_used
FROM 
    public.schools s
LEFT JOIN 
    public.school_users su ON s.id = su.school_id
LEFT JOIN 
    public.user_profiles u ON su.user_id = u.id
LEFT JOIN 
    public.token_usage t ON u.auth_id = t.user_id
GROUP BY 
    s.id, s.name; 