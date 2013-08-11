# Copyright (c) 2012, Jeremy Apthorp
# All rights reserved.

# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met: 

# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer. 
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution. 

# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# (MODIFIED BY BORIS BABENKO, 2013)

requestAnimationFrame = window.requestAnimationFrame or
  window.webkitRequestAnimationFrame or
  window.mozRequestAnimationFrame or
  window.oRequestAnimationFrame or
  window.msRequestAnimationFrame or
  (callback) ->
    window.setTimeout((-> callback 1000 / 60), 1000 / 60)

# TODO test this on other browsers
cancelAnimationFrame = window.cancelAnimationFrame or
  window.webkitCancelAnimationFrame or
  window.mozCancelAnimationFrame or
  window.oCancelAnimationFrame or
  window.msCancelAnimationFrame or
  window.clearTimeout

window.atom = atom = {}
atom.input = {
  _bindings: {}
  _down: {}
  _pressed: {}
  _released: []
  mouse: { x:0, y:0 }

  bind: (key, action) ->
    @_bindings[key] = action

  onkeydown: (e) ->
    action = @_bindings[eventCode e]
    return unless action

    @_pressed[action] = true unless @_down[action]
    @_down[action] = true

    e.stopPropagation()
    e.preventDefault()

  onkeyup: (e) ->
    action = @_bindings[eventCode e]
    return unless action
    @_released.push action
    e.stopPropagation()
    e.preventDefault()

  clearPressed: ->
    for action in @_released
      @_down[action] = false
    @_released = []
    @_pressed = {}

  pressed: (action) -> @_pressed[action]
  down: (action) -> @_down[action]
  released: (action) -> (action in @_released)

  onmousemove: (e) ->
    @mouse.x = e.pageX
    @mouse.y = e.pageY
  onmousedown: (e) -> @onkeydown(e)
  onmouseup: (e) -> @onkeyup(e)
  onmousewheel: (e) ->
    @onkeydown e
    @onkeyup e
  oncontextmenu: (e) ->
    if @_bindings[atom.button.RIGHT]
      e.stopPropagation()
      e.preventDefault()
}

document.onkeydown = atom.input.onkeydown.bind(atom.input)
document.onkeyup = atom.input.onkeyup.bind(atom.input)
document.onmouseup = atom.input.onmouseup.bind(atom.input)

atom.button =
  LEFT: -1
  MIDDLE: -2
  RIGHT: -3
  WHEELDOWN: -4
  WHEELUP: -5
atom.key =
  TAB: 9
  ENTER: 13
  ESC: 27
  SPACE: 32
  LEFT_ARROW: 37
  UP_ARROW: 38
  RIGHT_ARROW: 39
  DOWN_ARROW: 40

for c in [65..90]
  atom.key[String.fromCharCode c] = c

eventCode = (e) ->
  if e.type == 'keydown' or e.type == 'keyup'
    e.keyCode
  else if e.type == 'mousedown' or e.type == 'mouseup'
    switch e.button
      when 0 then atom.button.LEFT
      when 1 then atom.button.MIDDLE
      when 2 then atom.button.RIGHT
  else if e.type == 'mousewheel'
    if e.wheel > 0
      atom.button.WHEELUP
    else
      atom.button.WHEELDOWN

# atom.canvas = document.getElementsByTagName('canvas')[0]
# atom.canvas.style.position = "absolute"
# atom.canvas.style.top = "0"
# atom.canvas.style.left = "0"
atom.canvas = new fabric.StaticCanvas('game', {backgroundColor: '#fff'})
atom.canvasAR = 1.0

document.onmousemove = atom.input.onmousemove.bind(atom.input)
document.onmousedown = atom.input.onmousedown.bind(atom.input)
document.onmouseup = atom.input.onmouseup.bind(atom.input)
document.onmousewheel = atom.input.onmousewheel.bind(atom.input)
document.oncontextmenu = atom.input.oncontextmenu.bind(atom.input)

window.onresize = (e) ->
  windowAR = window.innerWidth / window.innerHeight
  if windowAR > atom.canvasAR
    atom.canvas.setHeight window.innerHeight
    atom.canvas.setWidth window.innerHeight*atom.canvasAR
  else
    atom.canvas.setHeight window.innerWidth/atom.canvasAR
    atom.canvas.setWidth window.innerWidth

  atom.width = atom.canvas.getWidth()
  atom.height = atom.canvas.getHeight()
  atom.resizeCb?()
window.onresize()

class Game
  constructor: ->
  update: (dt) ->
  draw: ->
  run: ->
    return if @running
    @running = true

    s = =>
      @frameRequest = requestAnimationFrame s
      @step()

    @last_step = Date.now()
    @frameRequest = requestAnimationFrame s
  stop: ->
    cancelAnimationFrame @frameRequest if @frameRequest
    @frameRequest = null
    @running = false
  step: ->
    if not @running
      return
    now = Date.now()
    dt = (now - @last_step) / 1000
    @last_step = now
    @update dt
    @draw()
    atom.input.clearPressed()

atom.Game = Game

## Audio

# TODO: firefox support
# TODO: streaming music

atom.audioContext = new webkitAudioContext?()

atom._mixer = atom.audioContext?.createGainNode()
atom._mixer?.connect atom.audioContext.destination

atom.loadSound = (url, callback) ->
  return callback? 'No audio support' unless atom.audioContext

  request = new XMLHttpRequest()
  request.open 'GET', url, true
  request.responseType = 'arraybuffer'

  request.onload = ->
    atom.audioContext.decodeAudioData request.response, (buffer) ->
      callback? null, buffer
    , (error) ->
      callback? error

  try
    request.send()
  catch e
    callback? e.message

atom.sfx = {}
atom.preloadSounds = (sfx, cb) ->
  return cb? 'No audio support' unless atom.audioContext
  # sfx is { name: 'url' }
  toLoad = 0
  for name, url of sfx
    toLoad++
    do (name, url) ->
      atom.loadSound "#{url}", (error, buffer) ->
        console.error error if error
        atom.sfx[name] = buffer if buffer
        cb?() unless --toLoad

atom.playSound = (name, time = 0) ->
  return unless atom.sfx[name] and atom.audioContext
  source = atom.audioContext.createBufferSource()
  source.buffer = atom.sfx[name]
  source.connect atom._mixer
  source.noteOn time
  source

atom.setVolume = (v) ->
  atom._mixer?.gain.value = v