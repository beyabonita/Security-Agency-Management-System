(() => {
  const root = document.documentElement;
  const userAgent = navigator.userAgent || '';
  const isIPadDesktopMode = navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1;
  const isAndroid = /Android/i.test(userAgent);
  const isMobile = /Android|Mobi|iPad|iPhone|iPod/i.test(userAgent) || isIPadDesktopMode;
  const message = document.getElementById('deviceMessage');
  const androidCard = document.getElementById('androidCard');
  const download = document.getElementById('androidDownload');

  if (isAndroid) {
    root.dataset.platform = 'android';
    androidCard.classList.add('is-detected');
    message.textContent = 'Android detected. Download and open the APK to install Sentinel Link.';
  } else if (isMobile) {
    root.dataset.platform = 'unsupported';
    message.textContent = 'Sentinel Link Guard currently supports Android devices only.';
    download.removeAttribute('href');
    download.removeAttribute('download');
    download.setAttribute('aria-disabled', 'true');
    download.classList.add('is-disabled');
    download.querySelector('span').textContent = 'Android devices only';
  } else {
    root.dataset.platform = 'desktop';
  }

  download.addEventListener('click', () => {
    const label = download.querySelector('span');
    const original = label.textContent;
    download.classList.add('is-starting');
    download.setAttribute('aria-label', 'Starting Sentinel Link Android download');
    label.textContent = 'Starting download…';
    window.setTimeout(() => {
      download.classList.remove('is-starting');
      download.removeAttribute('aria-label');
      label.textContent = original;
    }, 2200);
  });
})();
