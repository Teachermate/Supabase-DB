-- Drop everything and start fresh
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;

-- Grant necessary privileges
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO anon;
GRANT ALL ON SCHEMA public TO authenticated;
GRANT ALL ON SCHEMA public TO service_role;

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create enum types for better data integrity
CREATE TYPE user_role AS ENUM ('user', 'school_admin', 'super_admin');
CREATE TYPE user_status AS ENUM ('pending', 'active', 'inactive');
CREATE TYPE school_status AS ENUM ('active', 'inactive');
CREATE TYPE content_type AS ENUM ('lesson-plan', 'quiz', 'worksheet', 'presentation', 'assessment', 'pedagogy');

-- Create base tables with deferrable constraints
CREATE TABLE public.user_profiles (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    auth_id uuid UNIQUE NOT NULL,
    email text NOT NULL,
    first_name text NOT NULL,
    last_name text NOT NULL,
    mobile_number text,
    role user_role NOT NULL,
    status user_status NOT NULL DEFAULT 'pending',
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT fk_auth_user FOREIGN KEY (auth_id) 
        REFERENCES auth.users(id) 
        ON DELETE CASCADE 
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT unique_email UNIQUE(email)
);

CREATE TABLE public.schools (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    code text NOT NULL,
    status school_status NOT NULL DEFAULT 'active',
    credits_allocated integer NOT NULL DEFAULT 0,
    credits_used integer NOT NULL DEFAULT 0,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT unique_school_code UNIQUE(code)
);

CREATE TABLE public.school_users (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    school_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role text NOT NULL CHECK (role IN ('admin', 'teacher', 'staff')),
    status user_status NOT NULL DEFAULT 'active',
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT fk_school FOREIGN KEY (school_id) 
        REFERENCES public.schools(id) 
        ON DELETE CASCADE 
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT fk_user FOREIGN KEY (user_id) 
        REFERENCES public.user_profiles(id) 
        ON DELETE CASCADE 
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT unique_school_user UNIQUE(school_id, user_id)
);

CREATE TABLE public.content (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL,
    type content_type NOT NULL,
    subject text NOT NULL,
    grade text NOT NULL,
    chapter text NOT NULL,
    content text NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT fk_user FOREIGN KEY (user_id) 
        REFERENCES auth.users(id) 
        ON DELETE CASCADE 
        DEFERRABLE INITIALLY DEFERRED
);

-- Create indexes for better performance
CREATE INDEX idx_user_profiles_auth_id ON public.user_profiles(auth_id);
CREATE INDEX idx_user_profiles_email ON public.user_profiles(email);
CREATE INDEX idx_schools_code ON public.schools(code);
CREATE INDEX idx_school_users_school_id ON public.school_users(school_id);
CREATE INDEX idx_school_users_user_id ON public.school_users(user_id);
CREATE INDEX idx_content_user_id ON public.content(user_id);
CREATE INDEX idx_content_type ON public.content(type);

-- Create updated_at triggers
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_user_profiles_updated_at
    BEFORE UPDATE ON public.user_profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_schools_updated_at
    BEFORE UPDATE ON public.schools
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_school_users_updated_at
    BEFORE UPDATE ON public.school_users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_content_updated_at
    BEFORE UPDATE ON public.content
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Grant table-specific privileges
GRANT ALL ON TABLE public.user_profiles TO service_role;
GRANT ALL ON TABLE public.schools TO service_role;
GRANT ALL ON TABLE public.school_users TO service_role;
GRANT ALL ON TABLE public.content TO service_role;

-- Enable RLS
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.schools ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.content ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Users can view their own profile"
    ON public.user_profiles FOR SELECT
    USING (auth.uid() = auth_id);

CREATE POLICY "Users can update their own profile"
    ON public.user_profiles FOR UPDATE
    USING (auth.uid() = auth_id);

CREATE POLICY "Super admins can view all profiles"
    ON public.user_profiles FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles
            WHERE auth_id = auth.uid()
            AND role = 'super_admin'
        )
    );

CREATE POLICY "Allow profile creation during signup"
    ON public.user_profiles FOR INSERT
    WITH CHECK (true);

-- School policies
CREATE POLICY "Super admins can manage schools"
    ON public.schools FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles
            WHERE auth_id = auth.uid()
            AND role = 'super_admin'
        )
    );

CREATE POLICY "School admins can view their schools"
    ON public.schools FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.school_users su
            JOIN public.user_profiles up ON up.id = su.user_id
            WHERE up.auth_id = auth.uid()
            AND su.role = 'admin'
            AND su.school_id = schools.id
        )
    );

-- School users policies
CREATE POLICY "Super admins can manage school users"
    ON public.school_users FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles
            WHERE auth_id = auth.uid()
            AND role = 'super_admin'
        )
    );

CREATE POLICY "School admins can manage their school users"
    ON public.school_users FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM public.school_users su
            JOIN public.user_profiles up ON up.id = su.user_id
            WHERE up.auth_id = auth.uid()
            AND su.role = 'admin'
            AND su.school_id = school_users.school_id
        )
    );

-- Content policies
CREATE POLICY "Users can manage their own content"
    ON public.content FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Create function for super admin creation
CREATE OR REPLACE FUNCTION create_super_admin(
    p_email text,
    p_password text,
    p_first_name text,
    p_last_name text,
    p_mobile_number text
) RETURNS json AS $$
DECLARE
    v_user_id uuid;
    v_profile_id uuid;
BEGIN
    -- Start transaction with deferred constraints
    SET CONSTRAINTS ALL DEFERRED;
    
    -- Create user in auth.users
    INSERT INTO auth.users (
        instance_id,
        id,
        aud,
        role,
        email,
        encrypted_password,
        email_confirmed_at,
        last_sign_in_at,
        raw_app_meta_data,
        raw_user_meta_data,
        created_at,
        updated_at
    )
    VALUES (
        '00000000-0000-0000-0000-000000000000',
        gen_random_uuid(),
        'authenticated',
        'authenticated',
        p_email,
        crypt(p_password, gen_salt('bf', 10)),
        now(),
        now(),
        '{"provider": "email", "providers": ["email"]}'::jsonb,
        jsonb_build_object(
            'first_name', p_first_name,
            'last_name', p_last_name,
            'mobile_number', p_mobile_number,
            'role', 'super_admin'
        ),
        now(),
        now()
    )
    RETURNING id INTO v_user_id;

    -- Create user profile
    INSERT INTO public.user_profiles (
        auth_id,
        email,
        first_name,
        last_name,
        mobile_number,
        role,
        status
    )
    VALUES (
        v_user_id,
        p_email,
        p_first_name,
        p_last_name,
        p_mobile_number,
        'super_admin',
        'active'
    )
    RETURNING id INTO v_profile_id;

    RETURN json_build_object(
        'user_id', v_user_id,
        'profile_id', v_profile_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER; 