// Shared JS for the agent series site

function initTabs() {
  document.querySelectorAll('.tabs').forEach(tabs => {
    const buttons = tabs.querySelectorAll('button[data-tab]');
    const container = tabs.parentElement;
    const panels = container.querySelectorAll(':scope > .tab-panel');
    buttons.forEach(btn => {
      btn.addEventListener('click', () => {
        const target = btn.dataset.tab;
        buttons.forEach(b => b.classList.toggle('active', b === btn));
        panels.forEach(p => p.classList.toggle('active', p.dataset.tab === target));
      });
    });
  });
}

function initMermaid() {
  if (typeof mermaid === 'undefined') return;
  mermaid.initialize({
    startOnLoad: false,
    theme: 'base',
    securityLevel: 'loose',
    fontFamily: 'Inter, system-ui, sans-serif',
    themeVariables: {
      primaryColor: '#e0e7ff',
      primaryTextColor: '#1e1b4b',
      primaryBorderColor: '#6366f1',
      lineColor: '#6366f1',
      secondaryColor: '#ddd6fe',
      tertiaryColor: '#fce7f3',
      mainBkg: '#eef2ff',
      nodeBorder: '#6366f1',
      fontSize: '14px'
    },
    flowchart: { curve: 'basis', padding: 20 },
    sequence: { diagramMarginX: 30, diagramMarginY: 10 }
  });
  mermaid.run({ querySelector: '.mermaid' });
}

function copyToClipboard(text, el) {
  navigator.clipboard.writeText(text).then(() => {
    const orig = el.textContent;
    el.textContent = 'copied!';
    setTimeout(() => { el.textContent = orig; }, 1200);
  });
}

document.addEventListener('DOMContentLoaded', () => {
  initTabs();
  initMermaid();
});
