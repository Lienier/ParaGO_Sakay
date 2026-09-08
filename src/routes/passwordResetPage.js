const crypto = require('crypto');
module.exports = (_req, res) => {
  const nonce = crypto.randomBytes(24).toString('base64');
  res.set({ 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer',
    'Content-Security-Policy': `default-src 'none'; script-src 'nonce-${nonce}'; style-src 'nonce-${nonce}'; connect-src 'self'; form-action 'none'; base-uri 'none'; frame-ancestors 'none'` });
  res.type('html').send(`<!doctype html><html lang="en"><head><meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1"><title>Reset password — SakayGaray</title>
  <style nonce="${nonce}">body{font:18px system-ui;max-width:420px;margin:4rem auto;padding:24px}input,button{box-sizing:border-box;width:100%;padding:14px;margin:10px 0}button{cursor:pointer}</style></head>
  <body><h1>Reset your password</h1><form id="form"><label>New password<input id="password" type="password" autocomplete="new-password" minlength="8" maxlength="128" required></label><label>Confirm password<input id="confirm" type="password" autocomplete="new-password" required></label><button id="submit">Reset password</button></form><p id="message" role="status"></p>
  <script nonce="${nonce}">const token=location.hash.slice(1);history.replaceState(null,'',location.pathname);
  const form=document.getElementById('form'),message=document.getElementById('message'),button=document.getElementById('submit');
  if(!/^[a-f0-9]{64}$/.test(token)){form.hidden=true;message.textContent='Invalid link. Request a new password-reset email.';}
  form.addEventListener('submit',async e=>{e.preventDefault();const password=document.getElementById('password').value;
  if(password!==document.getElementById('confirm').value){message.textContent='Passwords do not match.';return;}button.disabled=true;
  try{const response=await fetch('/api/v1/auth/reset-password',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({token,newPassword:password})});
  const data=await response.json();if(!response.ok){message.textContent=data.message||'Unable to reset password.';const wait=Number(response.headers.get('Retry-After'))||0;if(wait>0){setTimeout(()=>button.disabled=false,wait*1000);return;}button.disabled=false;return;}
  form.hidden=true;message.textContent='Password updated. Return to SakayGaray and sign in again.';
  }catch(_){message.textContent='Connection unavailable. Please try again.';button.disabled=false;}});</script></body></html>`);
};
