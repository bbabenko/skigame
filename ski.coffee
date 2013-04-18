preload_assets = (callback) ->
  num_loaded = Object.keys(images).length + Object.keys(sounds).length
  for img_name, img_url of images
    ii = new Image();
    ii.onload = =>
      num_loaded--
      if num_loaded is 0
        callback?()
    ii.src = img_url

  atom.preloadSounds sounds, =>
    num_loaded -= Object.keys(sounds).length
    if num_loaded is 0
      callback?()

atom.canvasAR = 1

images = 
  skis: 'assets/skis.png'
  kn: 'assets/k+n.png'
  z: 'assets/z.png'
  cone: 'assets/cone.png'
  tree: 'assets/tree.png'
  sasha: 'assets/sasha.png'
  backdrop: 'assets/backdrop.jpg'

sounds = 
  ouch: 'assets/ouch.wav'

overlay = $('#overlay')
message_start = $('#game-start')
message_end = $('#game-end')
btn = $('#button')
game = null

atom.resizeCb = ->
  game?.refresh_view()
  overlay.width(atom.width)
  overlay.height(atom.height)
  overlay.css
    left: $('#game').offset().left
    top: $('#game').offset().top
window.onresize()

start_game = ->
  game.reset()
  message_start.hide()
  overlay.hide()
  window.onblur = -> game.stop()
  window.onfocus = -> game.run()
  game.run()

class Game extends atom.Game
  constructor: ->
    super

    #### CONSTANTS
    @DF = 0.5 # focal distance
    @HF = 0.5 # focal height
    @DG = 0.5 # distance from runway to camera
    @L = 10 # runway length
    @RW = 4 # runway width
    @RW2 = @RW/2.0
    @SKI_WIDTH = @RW / 20.0

    @MAXXSPEED = 5
    @XACC = 1
    @XFRICTION = .5
    @OBS_FREQ = 5

    @CONE_HEIGHT = .8
    @CONE_WIDTH = .6
    # @SPEED = 3

    @LIFE_INCREASE_SPEED = .001
    @COLLISION_PRICE = 0.25

    @OBS_IMGS = ['kn', 'z', 'cone', 'sasha', 'tree']
    @OBS_WEIGHTS = [1, 1, 10, 1, 5]
    @OBS_BINS = []
    for o, i in @OBS_WEIGHTS
      for _ in [0...o]
        @OBS_BINS.push @OBS_IMGS[i]

    # keyboard setup
    atom.input.bind atom.key.LEFT_ARROW, 'left'
    atom.input.bind atom.key.RIGHT_ARROW, 'right'
    atom.input.bind atom.key.DOWN_ARROW, 'down'
    atom.input.bind atom.key.UP_ARROW, 'up'

    #### DRAWING STUFF
    @_draw_backdrop()

    # canvas setup
    @runway = new fabric.Polyline([{x: 1, y: 2}, {x: 100, y: 200}, {x: 887, y: 777}],
      {stroke: '#00f', fill: '#fff'}, false)
    atom.canvas.add(@runway)

    # skis
    fabric.Image.fromURL images.skis, (oImg) =>
      @skis = oImg
      @skis.scaleToWidth(atom.width * @SKI_WIDTH)
      # @skis.scaleToHeight(atom.height * 0.1)
      @skis.set
        left: atom.width / 2.0
        top: atom.height - atom.height*0.05
      atom.canvas.add(@skis)

    # life bar
    @lifebar = new fabric.Rect
      fill: '#f00'
      strokeWidth: 0
    @lifebar_shell = new fabric.Rect
      stroke: '#000'
      strokeWidth: 2
      fill: "rgba(0,0,0,0)"
    atom.canvas.add(@lifebar)
    atom.canvas.add(@lifebar_shell)
    @lifebar_shell.set
      top: atom.height/25
      left: atom.width - atom.width/10
      height: atom.height/50
      width: atom.width/8

    @points_text = new fabric.Text('points: 0',
      left: atom.width/10
      top: atom.height/25
      fontSize: atom.height/40
      fontWeight: "bold"
      fontFamily: "sans-serif"
      textAlign: "left"
    )
    atom.canvas.add(@points_text)

    #### GAME PARAMS
    @dx = 0.0
    @obstacles = []
    @time_since_last_obs = 0
    @time_to_next_obs = 0
    @life = 1.0
    @points = 0
    @time = 0
    @xspeed = 0
    @speedup = false

  update: (dt) ->
    ####
    # x speed and location

    # if atom.input.down 'left'
    #   @dx = Math.max -@RW2, @dx - dt * @XSPEED
    # else if atom.input.down 'right'
    #   @dx = Math.min @RW2, @dx + dt * @XSPEED

    if atom.input.down 'left'
      @xspeed = Math.max(-@MAXXSPEED, @xspeed - @XACC)
    else if atom.input.down 'right'
      @xspeed = Math.min(@MAXXSPEED, @xspeed + @XACC)
    else
      if @xspeed > 0
        @xspeed = Math.max(0, @xspeed - @XFRICTION)
      else
        @xspeed = Math.min(0, @xspeed + @XFRICTION)

    @dx = Math.max(-@RW2 + @SKI_WIDTH/2, Math.min(@RW2 - @SKI_WIDTH/2, @dx + dt*@xspeed))
    # console.log "dx #{@dx}, rw #{@RW2}, #{Math.abs(@dx - @RW2)}"
    if (@dx > 0 and Math.abs(@dx - @RW2 + @SKI_WIDTH/2) < 0.0001) or 
        (@dx < 0 and Math.abs(-@dx - @RW2 + @SKI_WIDTH/2) < 0.0001)
      # console.log "slowing down"
      @xspeed = 0
    # console.log "speed #{@xspeed}"

    ####
    # points and speedup
    if atom.input.down 'up'
      @speedup = true
      @points += (2*dt)
      console.log "speedup"
    else
      @speedup = false
      @points += dt
    @time += dt

    ####
    # obstacles
    to_remove = []
    for o in @obstacles
      # oldest last, so they end up in front
      o.update(dt)
      if o.is_colliding() or o.is_off_screen()
        o.remove_from_canvas()
        to_remove.push o
        if o.is_colliding()
          # console.log "colliding with #{o.id} #{o.type}, me at #{@dx}, obs at #{o.x}"
          @life -= @COLLISION_PRICE
          atom.playSound('ouch')

    @life = Math.min 1.0, @life + @LIFE_INCREASE_SPEED
    if @life < 0
      @game_over()
    @obstacles = @obstacles.filter (o) -> not (o in to_remove)

    # add new obstacles
    if @time_to_next_obs < @time_since_last_obs
      type = @OBS_BINS[Math.floor(Math.random()*@OBS_BINS.length)]
      @obstacles.unshift(new Obstacle(@, @CONE_HEIGHT, @_random_x_loc(@CONE_WIDTH), type))
      @time_since_last_obs = 0
      @time_to_next_obs = Math.random()/@get_speed()
    else
      @time_since_last_obs += dt


  draw: ->
    # runway
    points = [{x: @_calc_x(-@RW2,0), y: @_calc_y(0,0)},
              {x: @_calc_x(@RW2,0), y: @_calc_y(0,0)},
              {x: @_calc_x(@RW2,@L), y: @_calc_y(0,@L)},
              {x: @_calc_x(-@RW2,@L), y: @_calc_y(0,@L)},
              {x: @_calc_x(-@RW2,0), y: @_calc_y(0,0)}]
              # {x: @_calc_x(0,0), y: @_calc_y(0,0)},
              # {x: @_calc_x(0,@L), y: @_calc_y(0,@L)}]
    @runway.set({points: points})

    for o in @obstacles
      o.draw()

    @skis?.bringToFront()

    # life bar
    @lifebar.set
      top: atom.height/25
      left: atom.width - atom.width/10 - atom.width/16*(1-@life)
      height: atom.height/50
      width: atom.width/8*@life
    
    @lifebar_shell.bringToFront()
    @lifebar.bringToFront()

    @points_text.set 'text', "points: #{Math.round(@points)}"

    atom.canvas.renderAll()

  _calc_y: (oy, od, convert=true) ->
    y = ((@HF - oy) * @DF / (@DG + od) + @HF)
    if convert
      return @_sy(y)
    else
      return y

  _calc_x: (ox, od, convert=true) ->
    # ox is relative to the center of the runway
    x = (-@dx + ox) * @DF / (@DG + od) + 0.5
    if convert
      return @_sx(x)
    else
      return x

  _sx: (x) ->
    return x*atom.width

  _sy: (y) ->
    return y*atom.width

  _random_x_loc: (width) ->
    # return -0.7
    if Math.random() < 0.7
      return Math.random()*(@RW - width) - @RW2 + width/2.0
    else
      return @dx

  _draw_backdrop: ->
    _adjust_backdrop = (bd) ->
      bd.set 
        left: atom.width/2.0
        top: atom.height/2.0
      bd.sendToBack()
      # atom.canvas.remove(bd)
      # atom.canvas.add(bd)
      bd.scaleToHeight(atom.height)
      # console.log atom.height + " " + bd.height + " " + bd.get('scaleX')
    if @backdrop?
      _adjust_backdrop(@backdrop)
    else
      fabric.Image.fromURL images.backdrop, (oImg) =>
        @backdrop = oImg
        atom.canvas.add(@backdrop)
        _adjust_backdrop(@backdrop)

  get_speed: ->
    s = Math.max 1, @time/25
    if @speedup
      # Math.max(s, 10)
      s*3
    else
      s

  refresh_view: ->
    @_draw_backdrop()
    @skis?.scaleToWidth(atom.width * @SKI_WIDTH)
    @skis?.set
      left: atom.width / 2.0
      top: atom.height - atom.height*0.05
    @lifebar_shell.set
      top: atom.height/25
      left: atom.width - atom.width/10
      height: atom.height/50
      width: atom.width/8
    @points_text.set
      left: atom.width/10
      top: atom.height/25
      fontSize: atom.height/40
    @draw()

  reset: ->
    @life = 1
    @points = 0
    @time = 0
    for o in @obstacles
      o.remove_from_canvas()
    @obstacles = []
    @dx = 0
    @xspeed = 0

  game_over: ->
    @life = 0
    @stop()
    window.onfocus = null
    message_start.hide()
    message_end.html("You got #{Math.round(@points)} points, but then you lost :(")
    message_end.show()
    btn.html('Play again!')
    btn.show()
    btn.on 'click', start_game
    overlay.show()
        
class Obstacle
  @counter = 0
  constructor: (@game, @h, @x, @type) ->
    @d = @game.L
    fabric.Image.fromURL images[@type], (oImg) =>
      @shape = oImg
      if @game.running
        atom.canvas.add(@shape)
        @draw()
    @id = Obstacle.counter++

  draw: ->
    if not @shape?
      return
    @shape.set
      left: @game._calc_x(@x, @d)
      top: @game._calc_y(@h/2.0, @d)
    @shape.scaleToHeight(@game._calc_y(0, @d) - @game._calc_y(@h, @d))

  update: (dt) ->
    if not @shape?
      return
    @d -= @game.get_speed()*dt
    @shape.bringToFront()

  is_colliding: ->
    return @d < .1 and Math.abs(@game.dx - @x) <= @game.SKI_WIDTH

  is_off_screen: ->
    return @d <= 0

  remove_from_canvas: ->
    atom.canvas.remove(@shape)


$(document).ready ->
  overlay.show()
  btn.hide()
  message_start.hide()
  message_end.html("Loading game...")
  message_end.show()
  preload_assets ->
    game = new Game
    game.draw()
    btn.html('Start game!')
    btn.show()
    btn.on 'click', start_game
    message_start.show()
    message_end.hide()
