const img = document.getElementById('output');
const placeholder = document.getElementById('placeholder');
const title = document.getElementById('title');

const es = new EventSource('/stream');

es.onmessage = (e) => {
    const stream_data = JSON.parse(e.data)

    if (stream_data.mime === 'image/svg+xml') {
        img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(stream_data.img);
    } else {
        img.src = `data:${stream_data.mime};base64,` + stream_data.img;
    }

    img.style.display = 'block';
    placeholder.style.display = 'none';
    title.textContent = stream_data.message.cell_id
};

es.onerror = () => {
    placeholder.textContent = 'Connection to Foundry-NVIM lost.';
    placeholder.style.display = 'block';
};
