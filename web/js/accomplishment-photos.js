(function () {
  'use strict';
  window.loadAccomplishmentPhotos = async function (container, reports) {
    const attachments = reports.filter(report => report.photo_path);
    for (let i = 0; i < attachments.length; i += 4) {
      await Promise.all(attachments.slice(i, i + 4).map(async report => {
        const slot = [...container.querySelectorAll('[data-report-photo]')]
          .find(element => element.dataset.reportPhoto === report.id);
        if (!slot || !slot.isConnected) return;
        const load = async () => {
          slot.textContent = 'Loading photo report…';
          const showError = () => {
            if (!slot.isConnected) return;
            slot.replaceChildren(document.createTextNode('Photo could not be loaded. '));
            const retry = document.createElement('button');
            retry.type = 'button'; retry.className = 'action-btn btn-reports';
            retry.textContent = 'Retry photo'; retry.addEventListener('click', load);
            slot.append(retry);
          };
          try {
            const { data, error } = await appSupabase.storage.from('accomplishment-photos')
              .createSignedUrl(report.photo_path, 900);
            if (error || !data?.signedUrl) throw error || new Error('Photo unavailable');
            const url = new URL(data.signedUrl);
            if (url.protocol !== 'https:') throw new Error('Invalid photo address');
            if (!slot.isConnected) return;
            const link = document.createElement('a');
            link.href = url.href; link.target = '_blank'; link.rel = 'noopener noreferrer';
            link.setAttribute('aria-label', 'Open photo report at full size');
            const image = document.createElement('img');
            image.alt = 'Accomplishment photo report'; image.loading = 'lazy';
            image.style.cssText = 'display:block;width:100%;max-height:520px;object-fit:contain;border-radius:12px';
            image.addEventListener('error', showError, { once: true });
            image.src = url.href; link.append(image);
            const caption = document.createElement('span');
            caption.textContent = 'Open full-size photo'; caption.style.display = 'block';
            link.append(caption); slot.replaceChildren(link);
          } catch (_) { showError(); }
        };
        await load();
      }));
    }
  };
}());
