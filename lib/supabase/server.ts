import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
export function createClient(){
 const store=cookies();
 return createServerClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,{
  cookies:{getAll(){return store.getAll()},setAll(cs){try{cs.forEach(({name,value,options})=>store.set(name,value,options))}catch{}}}
 });
}
