-- Grant all permissions on user_subscriptions table to the authenticated and service_role roles
GRANT ALL ON TABLE public.user_subscriptions TO authenticated;
GRANT ALL ON TABLE public.user_subscriptions TO service_role;

-- Grant usage on the uuid_generate_v4 function
GRANT EXECUTE ON FUNCTION uuid_generate_v4() TO authenticated;
GRANT EXECUTE ON FUNCTION uuid_generate_v4() TO service_role;

-- Grant usage on the update_updated_at_column function
GRANT EXECUTE ON FUNCTION update_updated_at_column() TO authenticated;
GRANT EXECUTE ON FUNCTION update_updated_at_column() TO service_role; 