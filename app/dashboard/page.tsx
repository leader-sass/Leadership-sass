import Link from 'next/link';
import {redirect} from 'next/navigation';
import {createClient} from '@/lib/supabase/server';
export const dynamic='force-dynamic';

export default async function Page(){
  const s=createClient();
  const {data:{user}}=await s.auth.getUser();
  if(!user)redirect('/login');
  const {data:w}=await s.from('workspaces').select('id,name').eq('owner_id',user.id).maybeSingle();
  let f:any=null;
  if(w){
    const q=await s.from('funnels').select('id,slug,title,status').eq('workspace_id',w.id).limit(1).maybeSingle();
    f=q.data;
    if(f){
      const a=await s.from('assessments').select('id').eq('is_system_template',true).eq('is_active',true).limit(1).maybeSingle();
      if(a.data)await s.from('funnel_assessments').upsert({funnel_id:f.id,assessment_id:a.data.id});
    }
  }
  const {data:cs}=w?await s.from('candidates').select('id,stage,submissions(scores(total,band))').eq('workspace_id',w.id):{data:[]};
  const rows:any[]=cs||[];
  const completed=rows.filter(x=>x.stage!=='assessment_started'&&x.stage!=='new').length;
  const high=rows.filter(x=>x.submissions?.[0]?.scores?.band==='high').length;
  const medium=rows.filter(x=>x.submissions?.[0]?.scores?.band==='medium').length;
  const low=rows.filter(x=>x.submissions?.[0]?.scores?.band==='low').length;
  const interviews=rows.filter(x=>['interview_requested','interview_scheduled'].includes(x.stage)).length;
  const rate=rows.length?Math.round(completed/rows.length*100):0;
  return <main className="dash">
    <aside className="sidebar">
      <div className="brand"><span className="brandMark">L</span><div><strong>LeaderFlow</strong><small>نظام إدارة الاستقطاب</small></div></div>
      <nav className="sideNav"><Link className="active" href="/dashboard">لوحة التحكم</Link><Link href="/candidates">المرشحون</Link>{f&&<Link href={'/f/'+f.slug}>صفحة الاستقطاب</Link>}</nav>
      <div className="sideFoot"><small>مساحة العمل</small><strong>{w?.name||'مساحة العمل'}</strong></div>
    </aside>
    <section className="dashMain">
      <header className="dashHead"><div><span className="eyebrow">نظرة عامة</span><h1>لوحة القائد</h1><p>تابع رحلة المرشحين واتخذ قرارات المتابعة من مكان واحد.</p></div>{f&&<Link className="primaryBtn" href={'/f/'+f.slug}>فتح صفحة الاستقطاب ↗</Link>}</header>
      <div className="metricGrid">
        <article className="metric"><span>إجمالي المرشحين</span><strong>{rows.length}</strong><small>كل المسجلين عبر القمع</small></article>
        <article className="metric"><span>أكملوا التقييم</span><strong>{completed}</strong><small>معدل الإكمال {rate}%</small></article>
        <article className="metric"><span>أولوية مرتفعة</span><strong>{high}</strong><small>جاهزون للمراجعة أولًا</small></article>
        <article className="metric"><span>المقابلات</span><strong>{interviews}</strong><small>مطلوبة أو مجدولة</small></article>
      </div>
      <div className="dashGrid">
        <article className="panel"><div className="panelHead"><div><span className="eyebrow">Leader Score</span><h2>توزيع الأولويات</h2></div><Link href="/candidates">عرض المرشحين</Link></div>
          <div className="priorityRow"><div><span>مرتفعة</span><strong>{high}</strong></div><div className="progress"><i style={{width:(rows.length?high/rows.length*100:0)+'%'}}/></div></div>
          <div className="priorityRow"><div><span>متوسطة</span><strong>{medium}</strong></div><div className="progress medium"><i style={{width:(rows.length?medium/rows.length*100:0)+'%'}}/></div></div>
          <div className="priorityRow"><div><span>منخفضة</span><strong>{low}</strong></div><div className="progress low"><i style={{width:(rows.length?low/rows.length*100:0)+'%'}}/></div></div>
        </article>
        <article className="panel funnelPanel"><span className="eyebrow">القمع النشط</span><h2>{f?.title||'صفحة الاستقطاب'}</h2><p>شارك رابطك مع المرشحين. سيُحفظ كل تسجيل وتقييم تلقائيًا في نظام المتابعة.</p>{f?<><div className="slugBox">/f/{f.slug}</div><Link className="secondaryBtn" href={'/f/'+f.slug}>معاينة الصفحة</Link></>:<p>لا يوجد قمع مرتبط بالحساب.</p>}</article>
      </div>
    </section>
  </main>
}