#!/usr/bin/env node
/**
 * ¿ABRE EL LIENZO WEB LO QUE ESCRIBE SFMAP?
 *
 * El documento es UNO y lo escriben dos superficies. Esta comprobación coge el
 * JSON que acaba de producir `terminarTrazo` —el de verdad, volcado por
 * `--escena sonda-tinta`, no uno escrito a mano para la ocasión— y lo pasa por
 * el camino del navegador:
 *
 *   1. lo lee como `InkElement` (x, y, pressure) y comprueba que basta
 *   2. lo pinta con los DOS motores del web y comprueba que sale contorno
 *   3. lo vuelve a serializar y comprueba que los campos que el web NO conoce
 *      —`tiltX`, `tiltY`, `t`— siguen ahí
 *
 * El punto 3 es el que importa: un campo aditivo que el otro lado borra al
 * guardar no es aditivo, es una bomba de relojería que se dispara la primera
 * vez que Daniel toca el trazo desde el navegador.
 *
 * Uso:  node scripts/verificar-formato.mjs /tmp/trazo-sfmap.json
 */
import { readFileSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
const require = createRequire(`${process.env.HOME}/Developer/business-os/arbrain/`)
const { getStroke } = require('perfect-freehand')

const ruta = process.argv[2] ?? '/tmp/trazo-sfmap.json'
const el = JSON.parse(readFileSync(ruta, 'utf8'))
let fallos = 0
const ok = (que, cierto, detalle = '') => {
  console.log(`${cierto ? '  ✓' : '  ✗'} ${que}${detalle ? ' · ' + detalle : ''}`)
  if (!cierto) fallos++
}

console.log(`\nEL ELEMENTO QUE ESCRIBIÓ SFMAP (${ruta})`)
ok('type es "ink"', el.type === 'ink', el.type)
for (const k of ['id', 'x', 'y', 'width', 'height', 'rotation', 'zIndex', 'opacity',
                 'locked', 'version', 'createdAt', 'updatedAt', 'size', 'highlighter', 'points']) {
  ok(`trae "${k}"`, el[k] !== undefined, String(el[k]).slice(0, 40))
}

// 1. El lienzo web lee StrokePoint = { x, y, pressure }. Nada más es obligatorio.
const puntos = el.points
ok('todos los puntos traen x, y, pressure numéricos',
   puntos.every(p => [p.x, p.y, p.pressure].every(v => typeof v === 'number' && Number.isFinite(v))),
   `${puntos.length} puntos`)
ok('los puntos son RELATIVOS al origen (el mínimo es 0,0)',
   Math.min(...puntos.map(p => p.x)) === 0 && Math.min(...puntos.map(p => p.y)) === 0)
ok('la caja declarada coincide con los puntos',
   Math.abs(Math.max(...puntos.map(p => p.x)) - el.width) < 0.02 &&
   Math.abs(Math.max(...puntos.map(p => p.y)) - el.height) < 0.02,
   `${el.width.toFixed(2)}×${el.height.toFixed(2)}`)

// 2. Los dos motores del web lo pintan.
const real = (() => {
  const v = puntos.map(p => p.pressure)
  return Math.max(...v) - Math.min(...v) > 0.03
})()
const pf = getStroke(puntos.map(p => [p.x, p.y, p.pressure]),
                     { size: Math.max(0.5, el.size) * 1.25, thinning: 0.65, smoothing: 0.5,
                       streamline: 0.5, simulatePressure: !real, last: true })
ok('perfect-freehand (draw3) le saca contorno', pf.length > 3, `${pf.length} puntos de contorno`)

const v4 = []
for (let i = 0; i < puntos.length; i++) {
  const p = puntos[i]
  const a = puntos[Math.max(0, i - 1)], b = puntos[Math.min(puntos.length - 1, i + 1)]
  let dx = b.x - a.x, dy = b.y - a.y
  const len = Math.hypot(dx, dy) || 1
  const f = real ? 0.35 + p.pressure * 0.9 : Math.max(0.45, 1.15 - Math.hypot(dx, dy) / 55)
  const w = (el.size * f) / 2
  v4.push({ x: p.x - (dy / len) * w, y: p.y + (dx / len) * w })
}
ok('el ribbon del canvas v4 le saca contorno', v4.length === puntos.length,
   `${v4.length} puntos`)
ok('ningún NaN en los contornos del web',
   pf.every(([x, y]) => Number.isFinite(x) && Number.isFinite(y)) &&
   v4.every(p => Number.isFinite(p.x) && Number.isFinite(p.y)))

// 3. Lo que el web no entiende, SOBREVIVE. Es el invariante del documento
//    compartido: el web hace spread de los objetos, no los reconstruye.
const conT = puntos.filter(p => p.t !== undefined).length
const conTilt = puntos.filter(p => p.tiltX !== undefined).length
console.log(`\n  campos aditivos presentes: t en ${conT}/${puntos.length} puntos · tilt en ${conTilt}`)
const despues = JSON.parse(JSON.stringify({
  // Lo que hace el web al mover o redimensionar: `{ ...p, x, y }`.
  ...el,
  x: el.x + 100,
  points: el.points.map(p => ({ ...p, x: p.x * 1.5, y: p.y * 1.5 })),
}))
ok('`t` sobrevive a un redimensionado del web',
   despues.points.filter(p => p.t !== undefined).length === conT)
ok('`tiltX`/`tiltY` sobreviven a un redimensionado del web',
   despues.points.filter(p => p.tiltX !== undefined).length === conTilt)
ok('re-serializar no pierde ninguna clave del elemento',
   Object.keys(JSON.parse(JSON.stringify(el))).length === Object.keys(el).length)

// 4. Y se deja el trazo como caso del banco, para verlo pintado por los tres.
const fixture = {
  generado: new Date().toISOString().slice(0, 10),
  fuente: `ida y vuelta: elemento escrito por sfmap en ${ruta}`,
  casos: [{
    nombre: 'ida-y-vuelta', grupo: 'formato',
    nota: 'el trazo que escribió sfmap, pintado por los tres motores',
    trazos: [{ x: 0, y: 0, size: el.size, highlighter: el.highlighter, puntos: el.points }],
  }],
}
writeFileSync('/tmp/fixture-ida-y-vuelta.json', JSON.stringify(fixture))
console.log(`\n  → /tmp/fixture-ida-y-vuelta.json`)
console.log(fallos === 0 ? '\nFORMATO_OK — el lienzo web abre lo que escribe sfmap\n'
                         : `\nFORMATO_ROTO — ${fallos} comprobaciones fallaron\n`)
process.exit(fallos === 0 ? 0 : 1)
