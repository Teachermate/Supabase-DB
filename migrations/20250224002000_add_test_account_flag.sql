-- Add is_test_account flag to user_profiles
ALTER TABLE public.user_profiles
ADD COLUMN is_test_account BOOLEAN DEFAULT FALSE;

-- Add is_test_account flag to schools
ALTER TABLE public.schools
ADD COLUMN is_test_account BOOLEAN DEFAULT FALSE;

-- Create index for easy filtering of test accounts
CREATE INDEX idx_user_profiles_test_account ON public.user_profiles(is_test_account) WHERE is_test_account = TRUE;
CREATE INDEX idx_schools_test_account ON public.schools(is_test_account) WHERE is_test_account = TRUE;

-- Create a configuration table for app settings
CREATE TABLE IF NOT EXISTS public.app_settings (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL,
  description TEXT,
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Insert production mode setting
INSERT INTO public.app_settings (key, value, description)
VALUES ('production_mode', 'true', 'When true, test accounts are excluded from certain operations')
ON CONFLICT (key) DO NOTHING;

-- Create a function to check if we're in production mode
CREATE OR REPLACE FUNCTION public.is_production_mode()
RETURNS BOOLEAN AS $$
DECLARE
  production BOOLEAN;
BEGIN
  SELECT (value::text)::boolean INTO production
  FROM public.app_settings
  WHERE key = 'production_mode';
  
  RETURN COALESCE(production, FALSE);
END;
$$ LANGUAGE plpgsql;

-- Create a view for non-test users
CREATE OR REPLACE VIEW public.production_users AS
SELECT * FROM public.user_profiles
WHERE is_test_account = FALSE;

-- Create a view for non-test schools
CREATE OR REPLACE VIEW public.production_schools AS
SELECT * FROM public.schools
WHERE is_test_account = FALSE;

-- Add comment to explain test accounts
COMMENT ON COLUMN public.user_profiles.is_test_account IS 'Flag to identify test accounts that should not be included in production reports';
COMMENT ON COLUMN public.schools.is_test_account IS 'Flag to identify test schools that should not be included in production reports'; 