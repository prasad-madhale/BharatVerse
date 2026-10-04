-- Adds `delete_my_account()`, which the app's "Delete account" calls: paste it into the SQL editor and run it once. It
-- can be run again, and changes no table.
--
-- Copied from schema.sql's account-deletion section word for word (see tools/local-stack/tests).

-- Account deletion from the app: removes the caller's own auth.users row, which cascades to their users, likes and
-- saved_articles rows. SECURITY DEFINER because only the owner may delete from auth.users; auth.uid() keeps it to the
-- caller, and only a signed-in user may call it.
CREATE OR REPLACE FUNCTION delete_my_account()
RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
    DELETE FROM auth.users WHERE id = auth.uid();
$$;
REVOKE EXECUTE ON FUNCTION delete_my_account() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION delete_my_account() TO authenticated;
