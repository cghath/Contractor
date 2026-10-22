// Contact-sheet helper for Instagram reels (2026-10-22, tactics reels for the Contractor AI).
// Paste into the page with javascript_exec. Then call:  await sheet(t0, step, n)
// It hides Instagram's sign-up dialog, pauses the video, seeks t0, t0+step, ... (n frames),
// draws each frame into a full-window grid with its timestamp, and shows the grid on top of the
// page, ready for a screenshot. Call hideSheet() to remove it.
window.sheet = async function (t0, step, n) {
	document.querySelectorAll('[role=dialog]').forEach(e => { let p = e; for (let i = 0; i < 3 && p.parentElement && p.parentElement !== document.body; i++) p = p.parentElement; p.remove(); });
	const v = document.querySelector('video');
	if (!v) return 'no video';
	v.muted = true; v.pause();
	const W = window.innerWidth, H = window.innerHeight;
	const cols = Math.min(n, 4), rows = Math.ceil(n / cols);
	const fh = Math.floor(H / rows) - 4, fw = Math.floor(fh * v.videoWidth / v.videoHeight);
	let c = document.getElementById('__sheet');
	if (!c) { c = document.createElement('canvas'); c.id = '__sheet'; c.style.cssText = 'position:fixed;left:0;top:0;z-index:2147483647;background:#000'; document.body.appendChild(c); }
	c.width = W; c.height = H; c.style.display = 'block';
	const g = c.getContext('2d'); g.fillStyle = '#000'; g.fillRect(0, 0, W, H);
	const out = [];
	for (let i = 0; i < n; i++) {
		const t = t0 + i * step;
		if (t > v.duration) break;
		v.currentTime = t;
		await new Promise(r => v.addEventListener('seeked', r, { once: true }));
		await new Promise(r => setTimeout(r, 450));  // let the decoder paint the frame (black otherwise)
		const x = (i % cols) * (fw + 4), y = Math.floor(i / cols) * (fh + 4);
		g.drawImage(v, x, y, fw, fh);
		g.fillStyle = 'rgba(0,0,0,.7)'; g.fillRect(x, y, 58, 18);
		g.fillStyle = '#ff0'; g.font = 'bold 14px sans-serif'; g.fillText(t.toFixed(2) + 's', x + 3, y + 14);
		out.push(t);
	}
	return { duration: v.duration, frames: out, frameSize: [fw, fh] };
};
window.hideSheet = () => { const c = document.getElementById('__sheet'); if (c) c.style.display = 'none'; };
'sheet() ready';
