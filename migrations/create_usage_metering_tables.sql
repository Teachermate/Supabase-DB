-- Create an enum for the allocation type
CREATE TYPE allocation_type AS ENUM ('individual', 'school');

-- Create table for credit and token allocations
CREATE TABLE IF NOT EXISTS public.usage_allocations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    school_id UUID NULL, -- NULL for individual allocations
    allocation_type allocation_type NOT NULL,
    credits_allocated INTEGER NOT NULL DEFAULT 0,
    tokens_allocated INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    
    -- Ensure unique allocation per user or school
    CONSTRAINT unique_allocation UNIQUE (user_id, school_id, allocation_type)
);

-- Create table for usage tracking
CREATE TABLE IF NOT EXISTS public.usage_metrics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    school_id UUID NULL, -- NULL for individual usage
    content_id UUID NOT NULL, -- Reference to the generated content
    input_tokens INTEGER NOT NULL DEFAULT 0,
    output_tokens INTEGER NOT NULL DEFAULT 0,
    total_tokens INTEGER GENERATED ALWAYS AS (input_tokens + output_tokens) STORED,
    credits_used INTEGER NOT NULL DEFAULT 1, -- Default 1 credit per content
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- Create view for individual usage summary
CREATE OR REPLACE VIEW public.individual_usage_summary AS
SELECT 
    u.user_id,
    a.credits_allocated,
    a.tokens_allocated,
    COALESCE(SUM(u.credits_used), 0) as total_credits_used,
    a.credits_allocated - COALESCE(SUM(u.credits_used), 0) as balance_credits,
    COALESCE(SUM(u.total_tokens), 0) as cumulative_tokens_used
FROM usage_allocations a
LEFT JOIN usage_metrics u ON a.user_id = u.user_id
WHERE a.allocation_type = 'individual'
GROUP BY u.user_id, a.credits_allocated, a.tokens_allocated;

-- Create view for school usage summary
CREATE OR REPLACE VIEW public.school_usage_summary AS
SELECT 
    u.school_id,
    a.credits_allocated,
    a.tokens_allocated,
    COALESCE(SUM(u.credits_used), 0) as total_credits_used,
    a.credits_allocated - COALESCE(SUM(u.credits_used), 0) as balance_credits,
    COALESCE(SUM(u.total_tokens), 0) as cumulative_tokens_used
FROM usage_allocations a
LEFT JOIN usage_metrics u ON a.school_id = u.school_id
WHERE a.allocation_type = 'school'
GROUP BY u.school_id, a.credits_allocated, a.tokens_allocated;

-- Add RLS policies
ALTER TABLE public.usage_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.usage_metrics ENABLE ROW LEVEL SECURITY;

-- Policy for users to view their own allocations
CREATE POLICY "Users can view their own allocations" 
    ON public.usage_allocations 
    FOR SELECT 
    USING (auth.uid() = user_id);

-- Policy for users to view their own usage metrics
CREATE POLICY "Users can view their own usage metrics" 
    ON public.usage_metrics 
    FOR SELECT 
    USING (auth.uid() = user_id);

-- Policy for school admins to view school allocations and metrics
CREATE POLICY "School admins can view school data" 
    ON public.usage_allocations 
    FOR SELECT 
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles 
            WHERE auth_id = auth.uid() 
            AND role = 'school_admin'
            AND school_id = usage_allocations.school_id
        )
    );

CREATE POLICY "School admins can view school metrics" 
    ON public.usage_metrics 
    FOR SELECT 
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles 
            WHERE auth_id = auth.uid() 
            AND role = 'school_admin'
            AND school_id = usage_metrics.school_id
        )
    );

-- Policy for super admins to manage all data
CREATE POLICY "Super admins can manage all allocations" 
    ON public.usage_allocations 
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles 
            WHERE auth_id = auth.uid() 
            AND role = 'super_admin'
        )
    );

CREATE POLICY "Super admins can manage all metrics" 
    ON public.usage_metrics 
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles 
            WHERE auth_id = auth.uid() 
            AND role = 'super_admin'
        )
    );

-- Create function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_usage_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for updated_at
CREATE TRIGGER update_usage_allocations_updated_at
    BEFORE UPDATE ON public.usage_allocations
    FOR EACH ROW
    EXECUTE FUNCTION update_usage_updated_at_column();

CREATE TRIGGER update_usage_metrics_updated_at
    BEFORE UPDATE ON public.usage_metrics
    FOR EACH ROW
    EXECUTE FUNCTION update_usage_updated_at_column();

-- Create indexes for better performance
CREATE INDEX idx_usage_allocations_user_id ON public.usage_allocations(user_id);
CREATE INDEX idx_usage_allocations_school_id ON public.usage_allocations(school_id);
CREATE INDEX idx_usage_metrics_user_id ON public.usage_metrics(user_id);
CREATE INDEX idx_usage_metrics_school_id ON public.usage_metrics(school_id);
CREATE INDEX idx_usage_metrics_content_id ON public.usage_metrics(content_id); 