const img = document.getElementById('output');
const placeholder = document.getElementById('placeholder');

const es = new EventSource('/stream');

es.onmessage = (e) => {
    const stream_data = JSON.parse(e.data)
    img.src = 'data:image/png;base64,' + stream_data.img_b64;
    img.style.display = 'block';
    placeholder.style.display = 'none';
    title.style.display = stream_data.message.data.cell_id
};

es.onerror = () => {
    placeholder.textContent = 'Connection to Foundry-NVIM lost.';
    placeholder.style.display = 'block';
};
