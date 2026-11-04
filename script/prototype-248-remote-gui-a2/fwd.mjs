// PROTOTYPE，不會 merge。把 127.0.0.1:<listen> 轉到 127.0.0.1:<target>（ec2 沒有 socat）。
// 用法：node fwd.mjs <listen> <target>
import net from 'node:net';

const [listen, target] = process.argv.slice(2).map(Number);
net.createServer((c) => {
  const u = net.connect(target, '127.0.0.1');
  c.pipe(u).pipe(c);
  c.on('error', () => u.destroy());
  u.on('error', () => c.destroy());
}).listen(listen, '127.0.0.1', () => console.log(`fwd 127.0.0.1:${listen} -> ${target}`));
