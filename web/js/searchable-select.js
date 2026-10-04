(function () {
  let sequence = 0;
  window.makeSearchableSelect = function (select) {
    if (!select || select.dataset.searchable) return;
    select.dataset.searchable = 'true';
    const wrap = document.createElement('div'); wrap.className = 'searchable-select';
    select.before(wrap); wrap.append(select); select.hidden = true;
    const input = document.createElement('input'); input.type = 'search'; input.className = 'form-control'; input.autocomplete = 'off';
    input.setAttribute('role', 'combobox'); input.setAttribute('aria-autocomplete', 'list'); input.setAttribute('aria-expanded', 'false');
    input.setAttribute('aria-label', [...select.labels].map(label => label.textContent.trim()).join(' ') || 'Search guard');
    input.id = select.id + '-search';
    [...select.labels].forEach(label => label.htmlFor = input.id);
    const list = document.createElement('div'); list.id = 'search-options-' + ++sequence; list.className = 'searchable-options'; list.setAttribute('role', 'listbox'); list.hidden = true;
    input.setAttribute('aria-controls', list.id); wrap.append(input, list);
    let active = -1;
    const close = () => { list.hidden = true; input.setAttribute('aria-expanded', 'false'); input.removeAttribute('aria-activedescendant'); };
    const sync = () => { input.disabled = select.disabled; input.placeholder = select.options[0]?.textContent || 'Search guard'; if (document.activeElement !== input) input.value = select.value ? select.selectedOptions[0]?.textContent || '' : ''; if (input.disabled) close(); };
    const choose = option => { select.value = option.value; input.value = option.value ? option.textContent : ''; close(); select.dispatchEvent(new Event('change', {bubbles:true})); };
    function render() {
      list.replaceChildren(); active = -1;
      const query = input.value.trim().toLocaleLowerCase();
      const options = [...select.options].filter(option => !option.disabled && !option.hidden && (!option.value || option.textContent.toLocaleLowerCase().includes(query)));
      for (const [index, option] of options.entries()) {
        const button = document.createElement('button'); button.type = 'button'; button.tabIndex = -1; button.id = list.id + '-' + index; button.setAttribute('role','option'); button.setAttribute('aria-selected',String(option.value === select.value)); button.textContent = option.textContent;
        button.addEventListener('mousedown', event => event.preventDefault()); button.onclick = () => choose(option); list.append(button);
      }
      if (!options.length) list.textContent = 'No matching guards.';
      list.hidden = false; input.setAttribute('aria-expanded','true');
    }
    input.addEventListener('focus', () => { input.value = ''; render(); });
    input.addEventListener('input', render);
    input.addEventListener('blur', () => { close(); input.value = select.value ? select.selectedOptions[0]?.textContent || '' : ''; });
    input.addEventListener('keydown', event => {
      if (event.key === 'Escape') { close(); return; }
      const items = [...list.querySelectorAll('button')];
      if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
        event.preventDefault(); if (list.hidden) render();
        const buttons = [...list.querySelectorAll('button')]; if (!buttons.length) return;
        active = (active + (event.key === 'ArrowDown' ? 1 : -1) + buttons.length) % buttons.length;
        buttons.forEach((item,i) => item.classList.toggle('is-active', i === active)); input.setAttribute('aria-activedescendant', buttons[active].id); buttons[active].scrollIntoView({block:'nearest'});
      } else if (event.key === 'Enter' && !list.hidden) { event.preventDefault(); (items[active] || items.find(item => item.textContent.toLowerCase() === input.value.toLowerCase()))?.click(); }
    });
    select.addEventListener('change', sync);
    new MutationObserver(() => { sync(); if (!list.hidden) render(); }).observe(select, {childList:true,subtree:true,attributes:true,attributeFilter:['disabled','hidden','selected']});
    sync();
  };
})();
