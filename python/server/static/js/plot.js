function renderPlot() {
    const wrapper = document.querySelector('#plot-container [data-created-at]');
    if (!wrapper) return;

    const dateEl = document.getElementById('created-date');
    if (dateEl && wrapper.dataset.createdAt) dateEl.innerText = wrapper.dataset.createdAt;

    const titleEl = document.getElementById('title-text');
    if (titleEl) titleEl.innerText = wrapper.dataset.title || '';

    const jsonStr = wrapper.dataset.plotJson;
    if (!jsonStr) return;

    try {
        const figure = JSON.parse(jsonStr);

        const plotEl = document.getElementById('plot');

        if (figure.layout && figure.layout.template) {
            const tmpl = figure.layout.template.layout;
            plotEl.style.backgroundColor = processPlotyColor(tmpl.paper_bgcolor);
            plotEl.style.setProperty('--li-text-color', processPlotyColor(tmpl.font.color));
        }

        figure.layout = figure.layout || {};
        figure.layout.width = plotEl.clientWidth;
        figure.layout.height = plotEl.clientHeight;

        Plotly.purge('plot');
        Plotly.newPlot('plot', figure);
    } catch (e) {
        console.error('Failed to render plot:', e);
    }
}

function rgbToHex(rgb) {
    const rgbValues = rgb.match(/\d+/g);
    const r = parseInt(rgbValues[0], 10);
    const g = parseInt(rgbValues[1], 10);
    const b = parseInt(rgbValues[2], 10);
    return '#' + (1 << 24 | r << 16 | g << 8 | b).toString(16).slice(1).toUpperCase();
}

function processPlotyColor(color) {
    if (color.startsWith('rgb(')) { return rgbToHex(color); }
    return color;
}

function toggleSelected(element) {
    const previouslySelected = document.querySelector('.plot-item.selected');
    if (previouslySelected) { previouslySelected.classList.remove('selected'); }
    element.classList.add('selected');
}

function renderThumbnails() {
    document.querySelectorAll('.plot-item-preview[data-plot-json]').forEach(function(el) {
        if (el.closest('li').querySelector('img')) return;
        try {
            const figure = JSON.parse(el.dataset.plotJson);

            const li = el.closest('li');

            // set list item colors from figure template
            if (li && figure.layout && figure.layout.template) {
                const tmpl = figure.layout.template.layout;
                li.style.backgroundColor = processPlotyColor(tmpl.paper_bgcolor);
                li.style.setProperty('--li-text-color', processPlotyColor(tmpl.font.color));
            }

            figure.layout = figure.layout || {};
            figure.layout.width = 500;
            figure.layout.height = 300;
            Plotly.toImage(figure, {format: 'png', height: 300, width: 500})
                .then(function(dataUrl) {
                    const img = document.createElement('img');
                    img.src = dataUrl;
                    img.style.width = '100%';
                    img.style.pointerEvents = 'none';
                    li.insertBefore(img, li.firstChild);
                })
                .catch(function(e) {
                    console.error('Failed to render thumbnail:', e);
                });
        } catch (e) {
            console.error('Failed to parse plot JSON:', e);
        }
    });
}
