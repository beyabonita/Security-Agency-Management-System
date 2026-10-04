(function(){
  const names='input[id$="FirstName"],input[id$="LastName"],input[id$="MiddleInitial"],input[name="firstName"],input[name="lastName"],input[name="middleInitial"],#first,#last';
  document.addEventListener('input',event=>{
    if(event.target.matches('#newGuardMobileNumber,input[name="mobileNumber"]')) {
      event.target.value=event.target.value.replace(/[^0-9]/g,'').slice(0,11);
      return;
    }
    if(!event.target.matches(names))return;
    const field=event.target,at=field.selectionStart;
    field.value=field.value.replace(/\p{N}/gu,'').replace(/(^|[\s\-])\p{L}/gu,letter=>letter.toLocaleUpperCase());
    field.setSelectionRange(Math.min(at,field.value.length),Math.min(at,field.value.length));
  });
  function enhance(){
    document.querySelectorAll('input[name="mobileNumber"]').forEach(field=>{
      field.type='tel';field.inputMode='numeric';field.maxLength=11;field.pattern='09[0-9]{9}';field.autocomplete='tel-national';
    });
    document.querySelectorAll('input[type="password"]').forEach(field=>{
      if(field.dataset.visibilityReady||field.closest('.password-wrap')||field.id==='currentPassword')return;
      field.dataset.visibilityReady='true';
      const wrap=document.createElement('div');wrap.style.cssText='position:relative;display:flex;align-items:center';field.before(wrap);wrap.append(field);field.style.paddingRight='72px';
      const button=document.createElement('button');button.type='button';button.textContent='Show';button.setAttribute('aria-label','Show '+(field.labels?.[0]?.textContent||'password'));button.style.cssText='position:absolute;right:8px;border:0;background:transparent;color:var(--sl-danger);font:inherit;font-size:12px;cursor:pointer';
      button.onclick=()=>{const visible=field.type==='password';field.type=visible?'text':'password';button.textContent=visible?'Hide':'Show';button.setAttribute('aria-label',(visible?'Hide ':'Show ')+(field.labels?.[0]?.textContent||'password'));};wrap.append(button);
    });
  }
  new MutationObserver(enhance).observe(document.body,{childList:true,subtree:true});enhance();
})();
