'use strict'

const fs = require('node:fs')
const path = require('node:path')
const mineflayer = require('mineflayer')

const username = 'bot_7e3a9c'
const configPath = path.join(__dirname, 'bot.json')
const config = JSON.parse(fs.readFileSync(configPath, 'utf8'))
const authPassword = fs.readFileSync(path.join(__dirname, 'authme-password'), 'utf8').trim()
let retryTimer

function connect () {
  const bot = mineflayer.createBot({
    host: '127.0.0.1',
    port: 25565,
    username,
    auth: 'offline',
    version: '26.2'
  })

  bot.on('login', () => console.log(`${new Date().toISOString()} logged in as ${username}`))
  bot.on('spawn', () => {
    console.log(`${new Date().toISOString()} spawned`)
    setTimeout(() => {
      if (bot.player) bot.chat(`/register ${authPassword} ${authPassword}`)
    }, 1500)
    setTimeout(() => {
      if (bot.player) bot.chat(`/login ${authPassword}`)
    }, 4000)
  })
  bot.on('kicked', reason => console.error(`${new Date().toISOString()} kicked: ${JSON.stringify(reason)}`))
  bot.on('error', error => console.error(`${new Date().toISOString()} error: ${error.message}`))
  bot.on('end', reason => {
    console.error(`${new Date().toISOString()} disconnected: ${reason || 'connection ended'}`)
    clearTimeout(retryTimer)
    retryTimer = setTimeout(connect, 5000)
    retryTimer.unref()
  })
}

if (!config.enabled) {
  console.error('Bot is disabled in bot.json')
  process.exit(1)
}

connect()
