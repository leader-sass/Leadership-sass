import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';

type CookieToSet = {
  name: string;
  value: string;
  options?: Parameters<ReturnType<typeof cookies>['set']>[2];
};

export function createClient() {
  const store = cookies();
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    {
      cookies: {
        getAll() {
          return store.getAll();
        },
        setAll(cookiesToSet: CookieToSet[]) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              store.set(name, value, options)
            );
          } catch {
            // Server Components cannot always write cookies.
          }
        },
      },
    }
  );
}
