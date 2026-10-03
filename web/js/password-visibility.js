(function() {
  const button = document.getElementById('passwordToggle');
  const password = document.getElementById('password');
  if (!button || !password) return;
  button.innerHTML = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/><path data-password-slash d="m3 3 18 18" style="display:none"/></svg>';
  button.setAttribute('aria-label','Show password');
  button.addEventListener('click',function(){
    const visible = password.type === 'password';
    password.type = visible ? 'text' : 'password';
    button.setAttribute('aria-label',visible ? 'Hide password' : 'Show password');
    button.setAttribute('aria-pressed',String(visible));
    button.querySelector('[data-password-slash]').style.display = visible ? '' : 'none';
    password.focus();
  });
})();
