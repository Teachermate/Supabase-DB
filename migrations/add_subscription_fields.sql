-- Add subscription fields to user_profiles table
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS subscription_status TEXT DEFAULT 'trial';
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS trial_start_date TIMESTAMPTZ;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS trial_end_date TIMESTAMPTZ;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS subscription_start_date TIMESTAMPTZ;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS subscription_end_date TIMESTAMPTZ;

-- Update test users to have subscription_status = 'test'
UPDATE user_profiles
SET 
  subscription_status = 'test',
  trial_start_date = NULL,
  trial_end_date = NULL,
  subscription_start_date = NULL,
  subscription_end_date = NULL
WHERE is_test_account = true;

-- Update super admins to have subscription_status = 'subscriber' with no end date
UPDATE user_profiles
SET 
  subscription_status = 'subscriber',
  trial_start_date = NULL,
  trial_end_date = NULL,
  subscription_start_date = CURRENT_TIMESTAMP,
  subscription_end_date = NULL
WHERE role = 'super_admin';

-- Update school admins to have subscription_status = 'subscriber' with end date
UPDATE user_profiles
SET 
  subscription_status = 'subscriber',
  trial_start_date = NULL,
  trial_end_date = NULL,
  subscription_start_date = CURRENT_TIMESTAMP,
  subscription_end_date = '2026-04-30 23:59:59'::TIMESTAMPTZ
WHERE role = 'school_admin' AND is_test_account = false;

-- Update regular users to have subscription_status = 'trial' with 30-day trial
UPDATE user_profiles
SET 
  subscription_status = 'trial',
  trial_start_date = CURRENT_TIMESTAMP,
  trial_end_date = CURRENT_TIMESTAMP + INTERVAL '30 days',
  subscription_start_date = NULL,
  subscription_end_date = NULL
WHERE role = 'user' AND is_test_account = false; 