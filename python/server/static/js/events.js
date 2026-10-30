var resizeTimeout;
window.addEventListener('resize', function() {
    clearTimeout(resizeTimeout);
    resizeTimeout = setTimeout(renderPlot, 100);
});

document.addEventListener('DOMContentLoaded', function() {
    const recentPlots = document.getElementById('recent-plots');
    if (recentPlots) {
        recentPlots.addEventListener('click', function(e) {
            const li = e.target.closest('li.plot-item');
            if (li) { toggleSelected(li); }
        });
    }

    const firstPlotItem = document.querySelector('#recent-plots li.plot-item');
    if (firstPlotItem) { toggleSelected(firstPlotItem); }

    renderPlot();
    renderThumbnails();
});

document.body.addEventListener('htmx:afterSettle', function(e) {
    if (e.target.id === 'plot-container') {
        renderPlot();
    }
});

document.body.addEventListener('htmx:sseOpen', function() {
    const ci = document.getElementById('connection-indicator');
    if (ci) ci.innerText = '🟢';
});

document.body.addEventListener('htmx:sseError', function() {
    const ci = document.getElementById('connection-indicator');
    if (ci) ci.innerText = '🔴';
});

document.body.addEventListener('htmx:afterSwap', function(e) {
    if (e.target.id !== 'recent-plots') return;

    renderThumbnails();

    const firstItem = document.querySelector('#recent-plots li.plot-item');
    if (!firstItem) return;
    toggleSelected(firstItem);

    htmx.ajax('GET', firstItem.getAttribute('hx-get'), {target: '#plot-container', swap: 'innerHTML'});
});
