
-- Create user_subscriptions table
CREATE TABLE IF NOT EXISTS public.user_subscriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL CHECK (status IN ('trial', 'subscriber', 'test')),
    trial_start_date TIMESTAMP WITH TIME ZONE,
    trial_end_date TIMESTAMP WITH TIME ZONE,
    subscription_start_date TIMESTAMP WITH TIME ZONE,
    subscription_end_date TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    
    -- Ensure only one subscription record per user
    CONSTRAINT unique_user_subscription UNIQUE (user_id)
);

-- Add RLS policies
ALTER TABLE public.user_subscriptions ENABLE ROW LEVEL SECURITY;

-- Policy for users to view their own subscription
CREATE POLICY "Users can view their own subscription" 
    ON public.user_subscriptions 
    FOR SELECT 
    USING (auth.uid() = user_id);

-- Policy for users to update their own subscription (if needed in the future)
CREATE POLICY "Users can update their own subscription" 
    ON public.user_subscriptions 
    FOR UPDATE 
    USING (auth.uid() = user_id);

-- Policy for service role and super admins to manage all subscriptions
CREATE POLICY "Service role can manage all subscriptions" 
    ON public.user_subscriptions 
    USING (
        -- Service role check would be handled by the service role key
        -- This is for super admins
        EXISTS (
            SELECT 1 FROM public.user_profiles 
            WHERE auth_id = auth.uid() 
            AND role = 'super_admin'
        )
    );

-- Create function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to update updated_at on update
CREATE TRIGGER update_user_subscriptions_updated_at
BEFORE UPDATE ON public.user_subscriptions
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

-- Create index for faster lookups
CREATE INDEX idx_user_subscriptions_user_id ON public.user_subscriptions(user_id);
CREATE INDEX idx_user_subscriptions_status ON public.user_subscriptions(status);
