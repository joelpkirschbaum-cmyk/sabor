// Generate PWA icons for Sabor — pure Node.js, no dependencies
// Creates a stylized "S" with orange brand color on dark background
// Run: node generate-icons.js

const zlib = require('zlib');
const fs = require('fs');

function createPNG(width, height, pixels) {
  // PNG signature
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

  function chunk(type, data) {
    const buf = Buffer.alloc(4 + type.length + data.length + 4);
    buf.writeUInt32BE(data.length, 0);
    buf.write(type, 4);
    data.copy(buf, 4 + type.length);
    const crc = crc32(Buffer.concat([Buffer.from(type), data]));
    buf.writeInt32BE(crc, buf.length - 4);
    return buf;
  }

  // CRC32
  const crcTable = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    crcTable[n] = c;
  }
  function crc32(buf) {
    let c = -1;
    for (let i = 0; i < buf.length; i++) c = crcTable[(c ^ buf[i]) & 0xFF] ^ (c >>> 8);
    return c ^ -1;
  }

  // IHDR
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 2; // RGB
  ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;

  // IDAT — raw image data with filter byte 0 per row
  const raw = Buffer.alloc(height * (1 + width * 3));
  for (let y = 0; y < height; y++) {
    raw[y * (1 + width * 3)] = 0; // filter none
    for (let x = 0; x < width; x++) {
      const si = (y * width + x) * 3;
      const di = y * (1 + width * 3) + 1 + x * 3;
      raw[di] = pixels[si];
      raw[di + 1] = pixels[si + 1];
      raw[di + 2] = pixels[si + 2];
    }
  }
  const compressed = zlib.deflateSync(raw);

  // IEND
  const iend = Buffer.alloc(0);

  return Buffer.concat([
    signature,
    chunk('IHDR', ihdr),
    chunk('IDAT', compressed),
    chunk('IEND', iend)
  ]);
}

function drawIcon(size) {
  const pixels = new Uint8Array(size * size * 3);

  function setPixel(x, y, r, g, b) {
    if (x < 0 || x >= size || y < 0 || y >= size) return;
    x = Math.floor(x); y = Math.floor(y);
    const i = (y * size + x) * 3;
    pixels[i] = r; pixels[i + 1] = g; pixels[i + 2] = b;
  }

  function blend(x, y, r, g, b, a) {
    if (x < 0 || x >= size || y < 0 || y >= size) return;
    x = Math.floor(x); y = Math.floor(y);
    const i = (y * size + x) * 3;
    pixels[i] = Math.round(pixels[i] * (1 - a) + r * a);
    pixels[i + 1] = Math.round(pixels[i + 1] * (1 - a) + g * a);
    pixels[i + 2] = Math.round(pixels[i + 2] * (1 - a) + b * a);
  }

  function fillCircle(cx, cy, radius, r, g, b, alpha = 1) {
    const r2 = radius * radius;
    for (let dy = -radius - 1; dy <= radius + 1; dy++) {
      for (let dx = -radius - 1; dx <= radius + 1; dx++) {
        const d2 = dx * dx + dy * dy;
        if (d2 <= r2) {
          const a = Math.min(1, Math.max(0, (radius - Math.sqrt(d2)) * 1.5)) * alpha;
          blend(cx + dx, cy + dy, r, g, b, a);
        }
      }
    }
  }

  function fillRect(x0, y0, w, h, r, g, b) {
    for (let y = y0; y < y0 + h; y++)
      for (let x = x0; x < x0 + w; x++)
        setPixel(x, y, r, g, b);
  }

  // Background: dark (#0a0a0f)
  for (let i = 0; i < size * size; i++) {
    pixels[i * 3] = 10;
    pixels[i * 3 + 1] = 10;
    pixels[i * 3 + 2] = 15;
  }

  const cx = size / 2;
  const cy = size / 2;

  // Subtle radial glow
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const dx = x - cx, dy = y - cy;
      const dist = Math.sqrt(dx * dx + dy * dy) / (size * 0.45);
      if (dist < 1) {
        const a = (1 - dist) * 0.12;
        blend(x, y, 255, 107, 53, a);
      }
    }
  }

  // Draw "S" shape using arcs and filled circles
  const s = size / 512; // scale factor
  const thickness = 38 * s;

  // The S is made of two semicircles connected
  // Top arc: center at (cx, cy - 60*s), radius 75*s, right half (clockwise from top)
  // Bottom arc: center at (cx, cy + 60*s), radius 75*s, left half

  const topCy = cy - 55 * s;
  const botCy = cy + 55 * s;
  const arcR = 75 * s;

  // Draw S by tracing thick path
  function drawThickArc(acx, acy, radius, startAngle, endAngle, clockwise) {
    const steps = Math.max(200, Math.floor(radius * 4));
    const dir = clockwise ? 1 : -1;
    let totalAngle = endAngle - startAngle;
    if (clockwise && totalAngle < 0) totalAngle += Math.PI * 2;
    if (!clockwise && totalAngle > 0) totalAngle -= Math.PI * 2;

    for (let i = 0; i <= steps; i++) {
      const t = i / steps;
      const angle = startAngle + totalAngle * t;
      const px = acx + Math.cos(angle) * radius;
      const py = acy + Math.sin(angle) * radius;
      fillCircle(px, py, thickness, 255, 107, 53);
    }
  }

  // Top semicircle: from right going up and around to left
  drawThickArc(cx, topCy, arcR, 0, -Math.PI, false);

  // Bottom semicircle: from left going down and around to right
  drawThickArc(cx, botCy, arcR, Math.PI, 0, false);

  // Connecting line on the right: from top arc bottom to bottom arc top
  const connRx = cx + arcR;
  for (let y = topCy; y <= botCy; y++) {
    fillCircle(connRx - arcR * 2 + arcR, y, thickness, 255, 107, 53);
  }

  // Actually, let me redo this more carefully.
  // S shape: top-right curve, then diagonal, then bottom-left curve
  // Let's trace the S as a series of points

  // Clear and redraw
  for (let i = 0; i < size * size; i++) {
    pixels[i * 3] = 10;
    pixels[i * 3 + 1] = 10;
    pixels[i * 3 + 2] = 15;
  }
  // Glow again
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const dx = x - cx, dy = y - cy;
      const dist = Math.sqrt(dx * dx + dy * dy) / (size * 0.45);
      if (dist < 1) {
        const a = (1 - dist) * 0.12;
        blend(x, y, 255, 107, 53, a);
      }
    }
  }

  // Draw S as connected thick arcs
  const r1 = 68 * s; // radius of top curve
  const r2 = 68 * s; // radius of bottom curve
  const topCenter = { x: cx + 5 * s, y: cy - 58 * s };
  const botCenter = { x: cx - 5 * s, y: cy + 58 * s };
  const lineThick = 34 * s;

  // Top arc: from ~200° to ~-20° (right-opening C shape)
  for (let i = 0; i <= 300; i++) {
    const angle = (210 - i * 230 / 300) * Math.PI / 180;
    const px = topCenter.x + Math.cos(angle) * r1;
    const py = topCenter.y + Math.sin(angle) * r1;
    fillCircle(px, py, lineThick, 255, 107, 53);
  }

  // Bottom arc: from ~30° to ~200° (left-opening C shape, mirror of top)
  for (let i = 0; i <= 300; i++) {
    const angle = (30 + i * 230 / 300) * Math.PI / 180;
    const px = botCenter.x + Math.cos(angle) * r2;
    const py = botCenter.y + Math.sin(angle) * r2;
    fillCircle(px, py, lineThick, 255, 107, 53);
  }

  // Small fork accent top-right
  const forkX = cx + size * 0.28;
  const forkTop = cy - size * 0.32;
  const forkLen = size * 0.16;
  const forkW = Math.max(2, 3 * s);

  // Fork handle
  for (let y = forkTop; y < forkTop + forkLen; y++) {
    fillCircle(forkX, y, forkW, 180, 180, 180, 0.35);
  }
  // Fork prongs
  for (let p = -1; p <= 1; p++) {
    const px = forkX + p * 5 * s;
    for (let y = forkTop - size * 0.04; y < forkTop + size * 0.05; y++) {
      fillCircle(px, y, forkW * 0.7, 180, 180, 180, 0.3);
    }
  }

  return pixels;
}

// Generate all three sizes
[192, 512, 180].forEach(size => {
  const pixels = drawIcon(size);
  const png = createPNG(size, size, pixels);
  const name = size === 180 ? 'apple-touch-icon.png' : `icon-${size}.png`;
  fs.writeFileSync(name, png);
  console.log(`Created ${name} (${size}x${size}, ${png.length} bytes)`);
});

console.log('All icons generated!');
