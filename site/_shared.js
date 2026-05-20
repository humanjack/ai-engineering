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
      // Nodes
      primaryColor: '#ffffff',
      primaryTextColor: '#1e1b4b',
      primaryBorderColor: '#4f46e5',
      // Subgraph (cluster) styling
      clusterBkg: '#e0e7ff',
      clusterBorder: '#6366f1',
      titleColor: '#312e81',
      // Edges
      lineColor: '#4338ca',
      edgeLabelBackground: '#f3f4ff',
      // Secondary palette
      secondaryColor: '#fde68a',
      secondaryBorderColor: '#d97706',
      secondaryTextColor: '#1f1300',
      tertiaryColor: '#dcfce7',
      tertiaryBorderColor: '#16a34a',
      tertiaryTextColor: '#052e16',
      // Sequence diagram
      actorBkg: '#e0e7ff',
      actorBorder: '#4f46e5',
      actorTextColor: '#1e1b4b',
      actorLineColor: '#6366f1',
      signalColor: '#1f2937',
      signalTextColor: '#1f2937',
      labelBoxBkgColor: '#fef3c7',
      labelBoxBorderColor: '#d97706',
      labelTextColor: '#1f1300',
      noteBkgColor: '#fef9c3',
      noteBorderColor: '#a16207',
      noteTextColor: '#422006',
      activationBkgColor: '#c7d2fe',
      activationBorderColor: '#4338ca',
      // State diagram
      labelBackgroundColor: '#fef3c7',
      // General
      mainBkg: '#ffffff',
      nodeBorder: '#4f46e5',
      fontSize: '15px',
      background: '#ffffff'
    },
    flowchart: {
      curve: 'basis',
      padding: 16,
      nodeSpacing: 40,
      rankSpacing: 50,
      useMaxWidth: true,
      htmlLabels: true
    },
    sequence: {
      diagramMarginX: 24,
      diagramMarginY: 16,
      boxMargin: 10,
      messageMargin: 36,
      mirrorActors: false,
      useMaxWidth: true
    },
    state: { useMaxWidth: true }
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
