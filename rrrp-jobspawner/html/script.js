const app = document.getElementById('app');
const rail = document.getElementById('categoryRail');
const grid = document.getElementById('vehicleGrid');
const locationLabel = document.getElementById('locationLabel');
const statusLine = document.getElementById('statusLine');
const searchInput = document.getElementById('searchInput');
const closeBtn = document.getElementById('closeBtn');
const storeBtn = document.getElementById('storeBtn');

let state = {
  locationIndex: null,
  categories: {},
  activeCategory: null,
  busy: false
};

function resourceName() {
  return window.GetParentResourceName ? window.GetParentResourceName() : 'qbx-jobspawner';
}

async function fetchNui(name, data = {}) {
  const resp = await fetch(`https://${resourceName()}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data)
  });
  try { return await resp.json(); } catch (e) { return {}; }
}

function setStatus(text, type) {
  statusLine.textContent = text;
  statusLine.className = 'footer__status' + (type ? ' ' + type : '');
}

function renderRail() {
  rail.innerHTML = '';
  const names = Object.keys(state.categories);
  names.forEach((name) => {
    const btn = document.createElement('button');
    btn.className = 'rail__btn' + (name === state.activeCategory ? ' active' : '');
    btn.innerHTML = `<span>${name}</span><span class="rail__count">${state.categories[name].length}</span>`;
    btn.addEventListener('click', () => {
      state.activeCategory = name;
      renderRail();
      renderGrid();
    });
    rail.appendChild(btn);
  });
}

const CAR_ICON = `<svg class="vcard__icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M3 13l1.6-4.8A2 2 0 0 1 6.5 7h11a2 2 0 0 1 1.9 1.2L21 13" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>
  <rect x="2.5" y="13" width="19" height="5" rx="1.4" stroke="currentColor" stroke-width="1.6"/>
  <circle cx="7" cy="18.5" r="1.6" stroke="currentColor" stroke-width="1.6"/>
  <circle cx="17" cy="18.5" r="1.6" stroke="currentColor" stroke-width="1.6"/>
</svg>`;

const LOCK_ICON = `<svg class="vcard__icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect x="5" y="10.5" width="14" height="9.5" rx="1.4" stroke="currentColor" stroke-width="1.6"/>
  <path d="M8 10.5V7.5a4 4 0 0 1 8 0v3" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>
</svg>`;

function renderGrid() {
  grid.innerHTML = '';
  const list = state.categories[state.activeCategory] || [];
  const filter = searchInput.value.trim().toLowerCase();
  const filtered = list.filter(v => v.label.toLowerCase().includes(filter) || v.model.toLowerCase().includes(filter));

  if (filtered.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'fleet__empty';
    empty.textContent = 'No vehicles match.';
    grid.appendChild(empty);
    return;
  }

  filtered.forEach((v) => {
    const card = document.createElement('div');
    card.className = 'vcard' + (v.locked ? ' vcard--locked' : '');
    card.innerHTML = `
      <div class="vcard__info">
        ${v.locked ? LOCK_ICON : CAR_ICON}
        <div class="vcard__text">
          <div class="vcard__name">${v.label}</div>
          <div class="vcard__model">${v.model}</div>
        </div>
      </div>
      ${v.locked
        ? `<div class="vcard__rank">RANK ${v.requiredGrade}+</div>`
        : `<div class="vcard__deploy">DEPLOY</div>`}
    `;
    if (v.locked) {
      card.addEventListener('click', () => {
        setStatus(`Requires rank ${v.requiredGrade}.`, 'error');
      });
    } else {
      card.addEventListener('click', () => deployVehicle(v.model));
    }
    grid.appendChild(card);
  });
}

async function deployVehicle(model) {
  if (state.busy) return;
  state.busy = true;
  setStatus('Deploying vehicle...');

  const result = await fetchNui('spawnVehicle', { locationIndex: state.locationIndex, model });

  if (result && result.ok) {
    setStatus('Vehicle deployed.', 'success');
    setTimeout(closeMenu, 350);
  } else {
    setStatus((result && result.message) || 'Deploy failed.', 'error');
    state.busy = false;
  }
}

async function closeMenu() {
  app.classList.add('hidden');
  await fetchNui('closeMenu');
}

closeBtn.addEventListener('click', closeMenu);

storeBtn.addEventListener('click', async () => {
  if (state.busy) return;
  state.busy = true;
  setStatus('Storing vehicle...');
  const result = await fetchNui('storeVehicle');
  if (result && result.ok) {
    setStatus('Vehicle stored.', 'success');
    setTimeout(closeMenu, 300);
  } else {
    setStatus((result && result.message) || 'Nothing to store.', 'error');
    state.busy = false;
  }
});

searchInput.addEventListener('input', renderGrid);

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') closeMenu();
});

window.addEventListener('message', (event) => {
  const data = event.data;
  if (data.action === 'open') {
    state.locationIndex = data.locationIndex;
    state.categories = data.categories || {};
    state.activeCategory = Object.keys(state.categories)[0] || null;
    state.busy = false;

    locationLabel.textContent = data.label || 'Fleet Terminal';
    setStatus('Select a vehicle to deploy');
    searchInput.value = '';

    renderRail();
    renderGrid();
    app.classList.remove('hidden');
  } else if (data.action === 'close') {
    app.classList.add('hidden');
  }
});
