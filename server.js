const http = require('http');
const fs = require('fs');
const path = require('path');

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.json': 'application/json',
  '.js': 'application/javascript',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.css': 'text/css',
  '.ico': 'image/x-icon',
};

http.createServer((req, res) => {
  let url = req.url.split('?')[0];
  if (url === '/') url = '/Sabor.html';
  const filePath = path.join(__dirname, url);
  const ext = path.extname(filePath);
  const contentType = MIME[ext] || 'application/octet-stream';

  fs.access(filePath, fs.constants.F_OK, (err) => {
    if (err) {
      // Fallback to Sabor.html for SPA routing
      const fallback = path.join(__dirname, 'Sabor.html');
      res.setHeader('Content-Type', 'text/html; charset=utf-8');
      fs.createReadStream(fallback).pipe(res);
      return;
    }
    res.setHeader('Content-Type', contentType);
    fs.createReadStream(filePath).pipe(res);
  });
}).listen(8080, () => console.log('Listening on http://localhost:8080'));
