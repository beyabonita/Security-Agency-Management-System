(function(root,factory){const api=factory();if(typeof module==='object'&&module.exports)module.exports=api;if(root)root.PhLocationSearch=api;})(typeof globalThis!=='undefined'?globalThis:this,function(){
  const normalize=value=>String(value||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]+/g,' ').trim();
  const clean=value=>String(value||'').trim().replace(/\s+/g,' ');
  function variants(query,area=''){
    const q=clean(query), terms=[q];
    const expanded=q.replace(/\bbrgy\.?\s/gi,'Barangay ').replace(/\bsto\.?\s/gi,'Santo ').replace(/\bsta\.?\s/gi,'Santa ').replace(/\bst\.?\s/gi,'Saint ');
    if(expanded!==q)terms.push(expanded);
    if(/\btown\b/i.test(expanded))terms.push(expanded.replace(/\btown\b/gi,'Towne'));
    else if(/\btowne\b/i.test(expanded))terms.push(expanded.replace(/\btowne\b/gi,'Town'));
    if(terms.length===1 && q.split(',')[0].trim().split(/\s+/).length===2){const parts=q.split(',');terms.push([parts[0].replace(/\s+/g,''),...parts.slice(1)].join(','));}
    return [...new Set(terms)].slice(0,3).map(term=>[term,clean(area)].filter(Boolean).join(', '));
  }
  function kind(r){
    const category=r.category||r.class, type=r.addresstype||r.type;
    if(category==='highway'||['road','street'].includes(type))return 'roads';
    if(category==='place'||category==='boundary'||['city','town','village','suburb','neighbourhood','quarter','hamlet','municipality','state','province','region','island'].includes(type))return 'communities';
    return 'places';
  }
  function filter(results,query,type='all'){
    const q=normalize(query), compact=q.replaceAll(' ','');
    const seen=new Set();
    const score=r=>{const name=normalize(r.name||r.display_name?.split(',')[0]);return (name===q?100:name.replaceAll(' ','')===compact?90:name.startsWith(q)?60:0)+(normalize(r.display_name).includes(q)?20:0)+(Number(r.importance)||0);};
    return (Array.isArray(results)?results:[]).filter(r=>{
      if(String(r.address?.country_code).toLowerCase()!=='ph'||r.lat==null||r.lon==null||String(r.lat).trim()===''||String(r.lon).trim()==='')return false;
      const lat=Number(r.lat),lon=Number(r.lon);
      if(!Number.isFinite(lat)||!Number.isFinite(lon)||lat<4.2||lat>21.3||lon<116.4||lon>127)return false;
      if(type!=='all'&&kind(r)!==type)return false;
      const key=r.osm_type&&r.osm_id?`${r.osm_type}:${r.osm_id}`:`${normalize(r.name||r.display_name)}:${lat.toFixed(5)}:${lon.toFixed(5)}`;
      if(seen.has(key))return false;seen.add(key);return true;
    }).sort((a,b)=>score(b)-score(a));
  }
  function matchesSite(site,query,status='all'){
    return (status==='all'||(status==='active')===Boolean(site.active))&&normalize(query).split(' ').every(word=>normalize(`${site.label||''} ${site.address||''}`).includes(word));
  }
  return Object.freeze({normalize,variants,kind,filter,matchesSite});
});
