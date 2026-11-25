const tracks = [...document.querySelectorAll('.track')];
const search = document.getElementById('search');
const filter = document.getElementById('filter');

function applyFilter() {
  let count = 0;
  const query = search.value.toLocaleLowerCase();
  for (const track of tracks) {
    const status = track.dataset.status;
    const matches = filter.value === 'all' ||
      (filter.value === 'problems' ? status !== 'clean' : status === filter.value);
    track.hidden = !(matches && track.dataset.path.toLocaleLowerCase().includes(query));
    if (!track.hidden) count++;
  }
  const empty = document.getElementById('empty');
  empty.hidden = count !== 0;
  empty.textContent = !query && filter.value === 'problems'
    ? 'Проверка не нашла записей, которые нужно прослушать из-за возможной проблемы со звуком.'
    : 'По этому запросу ничего не найдено.';
}
search.addEventListener('input', applyFilter);
filter.addEventListener('change', applyFilter);
applyFilter();

const player = document.getElementById('player');
const playing = document.getElementById('playing');
const picker = document.getElementById('musicFiles');
const chooseMusic = document.getElementById('chooseMusic');
const accessStatus = document.getElementById('accessStatus');
let selectedFiles = new Map();
let folderChosen = false;
let pendingPlay = null;
let activeFile = null;
let activeURL = '';
let startAt = 0;
let activePreview = '';
let activePreviewRequest = null;

function audioPath(path) {
  return path.replace(/\\/g, '/').normalize('NFC');
}

function resetPlayer() {
  player.pause();
  player.removeAttribute('src');
  player.load();
  if (activeURL) URL.revokeObjectURL(activeURL);
  activeURL = '';
  activeFile = null;
  activePreview = '';
  activePreviewRequest = null;
}

function chooseFolder() {
  picker.value = '';
  picker.click();
}

function seekAndPlay() {
  if (!activeURL || player.currentSrc !== activeURL) return;
  const duration = player.duration;
  player.currentTime = Number.isFinite(duration)
    ? Math.min(startAt, Math.max(0, duration - .01)) : startAt;
  if (player.paused) requestPlayback();
}

function requestPlayback() {
  const requestedURL = activeURL;
  player.play().catch(() => {
    if (activeURL === requestedURL) {
      playing.textContent = 'Нажмите кнопку воспроизведения в плеере.';
    }
  });
}

const missingPreview = 'Этот фрагмент не подготовлен. Выберите папку с музыкой, чтобы послушать исходную запись.';
const unreadablePreview = 'Не удалось прочитать встроенный фрагмент. Выберите папку с музыкой, чтобы послушать исходную запись.';

function playTrack(path, start, label, notice = '', allowPicker = true) {
  const key = audioPath(path);
  const file = selectedFiles.get(key);
  if (!file) {
    const ambiguous = selectedFiles.has(key);
    playing.textContent = notice || (ambiguous
      ? 'Найдено несколько подходящих файлов «' + path + '». Выберите саму папку библиотеки, чтобы не перепутать записи.'
      : folderChosen
        ? 'В выбранной папке не найден файл «' + path + '». Выберите музыкальную папку из отчёта ещё раз.'
        : 'Для прослушивания исходной записи выберите папку с музыкой.');
    accessStatus.textContent = playing.textContent;
    pendingPlay = {path, start, label, notice};
    if (allowPicker && (!folderChosen || notice)) chooseFolder();
    return;
  }
  pendingPlay = null;
  startAt = Number.isFinite(start) && start > 0 ? start : 0;
  playing.textContent = path + (notice ? ' · исходная запись' : '') + (label ? ' · ' + label : '');
  if (activeFile === file && player.readyState >= 1) {
    seekAndPlay();
    return;
  }
  loadAudio(file);
}

function loadAudio(file) {
  player.pause();
  const previousURL = activeURL;
  activeFile = file;
  activePreview = '';
  activePreviewRequest = null;
  activeURL = URL.createObjectURL(file);
  player.src = activeURL;
  player.load();
  if (previousURL) URL.revokeObjectURL(previousURL);
  // Start inside the trusted click, then seek when metadata becomes available.
  requestPlayback();
}

function playPreview(button) {
  const previewID = button.dataset.previewId;
  const origin = Number(button.dataset.previewStart);
  const absoluteStart = Number(button.dataset.start);
  startAt = Math.max(0, absoluteStart - origin);
  playing.textContent = button.dataset.audioPath + ' · фрагмент ' + button.dataset.previewRange;
  if (activePreview === previewID && player.readyState >= 1) {
    seekAndPlay();
    return;
  }
  try {
    const encoded = document.getElementById(previewID).textContent.trim();
    const bytes = Uint8Array.from(atob(encoded), character => character.charCodeAt(0));
    if (bytes.length < 4) throw new Error('empty preview');
    loadAudio(new Blob([bytes], {type: 'audio/mpeg'}));
    activePreview = previewID;
    activePreviewRequest = {path: button.dataset.audioPath, start: absoluteStart, label: button.textContent};
  } catch (_) {
    playTrack(button.dataset.audioPath, absoluteStart, button.textContent, unreadablePreview);
  }
}

chooseMusic.addEventListener('click', chooseFolder);

picker.addEventListener('change', () => {
  if (picker.files.length === 0) return;
  resetPlayer();
  folderChosen = true;
  const wanted = new Set(tracks.map(track => audioPath(track.dataset.path)));
  const groups = new Map();
  for (const file of picker.files) {
    const relative = audioPath(file.webkitRelativePath || file.name);
    // Try whole report paths, longest first. Never fall back to just a basename.
    for (let offset = 0; offset >= 0;) {
      const path = relative.slice(offset);
      if (wanted.has(path)) {
        const prefix = relative.slice(0, offset);
        if (!groups.has(prefix)) groups.set(prefix, new Map());
        const group = groups.get(prefix);
        group.set(path, group.has(path) ? null : file);
        break;
      }
      const separator = relative.indexOf('/', offset);
      offset = separator < 0 ? -1 : separator + 1;
    }
  }
  const files = groups.size === 1 ? groups.values().next().value : new Map();
  if (groups.size > 1) {
    // Multiple library roots cannot safely be combined into one report.
    for (const group of groups.values()) for (const path of group.keys()) files.set(path, null);
  }
  selectedFiles = files;
  let available = 0;
  for (const track of tracks) {
    if (files.get(audioPath(track.dataset.path))) available++;
  }
  accessStatus.textContent = 'Доступно записей из отчёта: ' + available + ' из ' + tracks.length +
    '. Файлы используются локально в этой странице.';
  if (groups.size > 1 || [...files.values()].some(file => !file)) {
    accessStatus.textContent += ' Найдено несколько подходящих копий. Выберите саму папку библиотеки, чтобы не перепутать записи.';
  } else if (available < tracks.length) {
    accessStatus.textContent += ' Для отсутствующих записей выберите музыкальную папку из отчёта ещё раз.';
  }
  const request = pendingPlay;
  pendingPlay = null;
  if (request) playTrack(request.path, request.start, request.label, request.notice, false);
});

picker.addEventListener('cancel', () => { pendingPlay = null; });
player.addEventListener('loadedmetadata', seekAndPlay);
player.addEventListener('error', () => {
  if (activePreviewRequest) {
    const request = activePreviewRequest;
    resetPlayer();
    playTrack(request.path, request.start, request.label, unreadablePreview, false);
  } else if (activeFile) {
    playing.textContent = 'Браузер не смог воспроизвести выбранный файл. Этот формат можно прослушать во внешнем плеере. При изменении файла выберите папку заново.';
  }
});
for (const button of document.querySelectorAll('button[data-audio-path]')) {
  button.addEventListener('click', () => {
    if (button.dataset.previewId) {
      playPreview(button);
    } else {
      playTrack(button.dataset.audioPath, Number(button.dataset.start), button.textContent,
        button.dataset.previewUnavailable === 'true' ? missingPreview : '');
    }
  });
}
window.addEventListener('pagehide', resetPlayer);
