(() => {
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Footer year
  const year = document.getElementById('year');
  if (year) year.textContent = new Date().getFullYear();

  // Header border once the page scrolls
  const header = document.querySelector('.site-header');
  const onScroll = () => header.classList.toggle('scrolled', window.scrollY > 8);
  onScroll();
  window.addEventListener('scroll', onScroll, { passive: true });

  // Mobile menu
  const toggle = document.querySelector('.nav-toggle');
  const nav = document.getElementById('site-nav');
  const setMenu = (open) => {
    nav.classList.toggle('open', open);
    toggle.setAttribute('aria-expanded', String(open));
    toggle.textContent = open ? 'Close' : 'Menu';
  };
  toggle.addEventListener('click', () => setMenu(!nav.classList.contains('open')));
  nav.addEventListener('click', (e) => { if (e.target.closest('a')) setMenu(false); });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') setMenu(false); });

  // Highlight the nav link for the section in view
  const links = new Map([...nav.querySelectorAll('a[href^="#"]')].map((a) => [a.getAttribute('href').slice(1), a]));
  if ('IntersectionObserver' in window) {
    const spy = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        links.forEach((a) => a.classList.remove('active'));
        const link = links.get(entry.target.id);
        if (link) link.classList.add('active');
      });
    }, { rootMargin: '-45% 0px -50% 0px' });
    links.forEach((_, id) => { const el = document.getElementById(id); if (el) spy.observe(el); });
  }

  // PolyDial call panel: cycle greetings while it is on screen
  const greetings = [
    ['English', 'en', 'Hello! How can I help you today?'],
    ['French', 'fr', 'Bonjour ! Comment puis-je vous aider aujourd’hui ?'],
    ['Arabic', 'ar', 'مرحبًا! كيف يمكنني مساعدتك اليوم؟'],
    ['Spanish', 'es', '¡Hola! ¿En qué puedo ayudarle hoy?'],
    ['Japanese', 'ja', 'こんにちは！本日はどのようなご用件でしょうか？'],
    ['German', 'de', 'Hallo! Wie kann ich Ihnen heute helfen?'],
    ['Hindi', 'hi', 'नमस्ते! आज मैं आपकी क्या मदद कर सकता हूँ?'],
    ['Portuguese', 'pt-BR', 'Olá! Como posso ajudar você hoje?'],
    ['Mandarin', 'zh-CN', '您好！今天有什么可以帮您的吗？'],
    ['Turkish', 'tr', 'Merhaba! Bugün size nasıl yardımcı olabilirim?'],
    ['Korean', 'ko', '안녕하세요! 오늘 무엇을 도와드릴까요?'],
  ];
  const langEl = document.getElementById('call-lang');
  const greetEl = document.getElementById('call-greeting');
  const timeEl = document.getElementById('call-time');
  const panel = document.querySelector('.call');
  if (!langEl || !greetEl || !panel) return;

  let i = 0;
  let seconds = 12;
  let timer = null;

  const show = (idx) => {
    const [name, code, text] = greetings[idx];
    langEl.textContent = name;
    greetEl.textContent = text;
    greetEl.lang = code;
    greetEl.dir = code === 'ar' ? 'rtl' : 'ltr';
    greetEl.style.textAlign = code === 'ar' ? 'right' : '';
  };

  const step = () => {
    i = (i + 1) % greetings.length;
    if (reduceMotion) { show(i); return; }
    greetEl.classList.add('out');
    setTimeout(() => { show(i); greetEl.classList.remove('out'); }, 350);
  };

  const tick = () => {
    seconds += 1;
    const m = String(Math.floor(seconds / 60)).padStart(2, '0');
    const s = String(seconds % 60).padStart(2, '0');
    timeEl.textContent = `${m}:${s}`;
    if (seconds % 3 === 0) step();
  };

  const start = () => { if (!timer) timer = setInterval(tick, 1000); };
  const stop = () => { clearInterval(timer); timer = null; };

  if ('IntersectionObserver' in window) {
    new IntersectionObserver(([entry]) => (entry.isIntersecting ? start() : stop()), { threshold: 0.2 }).observe(panel);
  } else {
    start();
  }
  document.addEventListener('visibilitychange', () => { if (document.hidden) stop(); });
})();
