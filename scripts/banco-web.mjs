#!/usr/bin/env node
/**
 * LOS CONTORNOS DEL REFERENTE, para el A/B del motor de tinta.
 *
 * Corre los DOS motores del lienzo web sobre el MISMO fixture que sfmap y
 * escupe polígonos. No pinta nada: el rasterizado lo hace `--banco` con su
 * único contexto, porque si cada motor pintara en su propia pila el A/B
 * mediría el antialiasing del navegador tanto como la geometría.
 *
 *   web-pf  → perfect-freehand de verdad (el paquete de arbrain/node_modules),
 *             con los parámetros canónicos de `draw3/.../freehand-outline.ts`
 *   web-v4  → el ribbon de `features/canvas/render/engine.ts` (`inkOutline`),
 *             que es lo que HOY pinta este mismo documento en el navegador
 *
 * Uso:  node scripts/banco-web.mjs banco/trazos.json /tmp/banco
 */
import { readFileSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'

const require = createRequire(`${process.env.HOME}/Developer/business-os/arbrain/`)
const { getStroke } = require('perfect-freehand')

const [, , fixture = 'banco/trazos.json', salida = '/tmp/banco'] = process.argv
const doc = JSON.parse(readFileSync(fixture, 'utf8'))

// ── los parámetros canónicos del referente ─────────────────────────────────
const FREEDRAW_SIZE_FACTOR = 1.25
const FREEDRAW_THINNING = 0.65
const FREEDRAW_STREAMLINE = 0.5
const HIGHLIGHTER_THINNING = 0.15
const HIGHLIGHTER_STREAMLINE = 0.55
const PRESSURE_EPSILON = 0.03

function hasRealPressure(points) {
  let min = Infinity, max = -Infinity
  for (const p of points) {
    const v = typeof p.pressure === 'number' && Number.isFinite(p.pressure) ? p.pressure : 0.5
    if (v < min) min = v
    if (v > max) max = v
  }
  if (!Number.isFinite(min)) return false
  return max - min > PRESSURE_EPSILON
}

function pf(trazo) {
  const pts = trazo.puntos
  const input = pts.map(p => [p.x, p.y, Math.max(0, Math.min(1, p.pressure ?? 0.5))])
  const marcador = !!trazo.highlighter
  const out = getStroke(input, {
    size: marcador ? Math.max(0.5, trazo.size) : Math.max(0.5, trazo.size) * FREEDRAW_SIZE_FACTOR,
    thinning: marcador ? HIGHLIGHTER_THINNING : FREEDRAW_THINNING,
    smoothing: 0.5,
    streamline: marcador ? HIGHLIGHTER_STREAMLINE : FREEDRAW_STREAMLINE,
    simulatePressure: !hasRealPressure(pts),
    last: true,
  })
  return out.map(([x, y]) => ({ x, y }))
}

/** `inkOutline` de features/canvas/render/engine.ts, sin una coma de más. */
function v4(trazo) {
  const pts = trazo.puntos
  if (pts.length < 2) return []
  const real = pts.length >= 4 && (() => {
    let min = Infinity, max = -Infinity
    for (const p of pts) { const v = p.pressure ?? 0.5; if (v < min) min = v; if (v > max) max = v }
    return max - min > 0.03
  })()
  const left = [], right = []
  for (let i = 0; i < pts.length; i++) {
    const p = pts[i]
    const prev = pts[Math.max(0, i - 1)], next = pts[Math.min(pts.length - 1, i + 1)]
    let dx = next.x - prev.x, dy = next.y - prev.y
    const len = Math.hypot(dx, dy) || 1
    dx /= len; dy /= len
    const speed = Math.hypot(next.x - prev.x, next.y - prev.y)
    const factor = real ? 0.35 + (p.pressure ?? 0.5) * 0.9 : Math.max(0.45, 1.15 - speed / 55)
    const w = (trazo.size * factor) / 2
    left.push({ x: p.x - dy * w, y: p.y + dx * w })
    right.push({ x: p.x + dy * w, y: p.y - dx * w })
  }
  return [...left, ...right.reverse()]
}

for (const [nombre, fn] of [['web-pf', pf], ['web-v4', v4]]) {
  const mapa = {}
  for (const caso of doc.casos) mapa[caso.nombre] = caso.trazos.map(fn)
  const ruta = `${salida}/contornos-${nombre}.json`
  writeFileSync(ruta, JSON.stringify(mapa))
  const n = Object.values(mapa).flat().reduce((a, p) => a + p.length, 0)
  console.log(`${nombre}: ${Object.keys(mapa).length} casos, ${n} puntos de contorno → ${ruta}`)
}
