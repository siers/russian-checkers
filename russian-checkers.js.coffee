EMPTY    = null
BLACK    = false
WHITE    = true
REGULAR  = false
QUEEN    = true # Must be always true.
X        = 0
Y        = 1

flip = (cons) ->
  [7 - cons[X], 7 - cons[Y]]

# This is a mixin, and rules /logically/ actually extend piece, not vice versa.
class Rules
  bound = (cons) ->
    [x, y] = cons ? @target
    x >= 0 and x <= 7 and y >= 0 and y <= 7
  bound: bound

  direction: ->
    if @color == BLACK then 1 else -1

  # Checks whether on a black square only.
  @black = (cons) ->
    [x, y] = cons ? @target
    (x + y) % 2 == 1
  black: @black

  diagonal: ->
    x = @cons[X] - @target[X]
    y = @cons[Y] - @target[Y]
    Math.abs(x) == Math.abs(y)

  # Check that space where it's going is empty.
  empty: ->
    x    = @target[X] - @cons[X]
    y    = @target[Y] - @cons[Y]
    vec  = [x / Math.abs(x), y / Math.abs(y)]
    tile = @cons

    until _.isEqual(tile, @target)
      tile = [tile[X] + vec[X], tile[Y] + vec[Y]]
      return false if @set.get(tile)
    return true

  # Checks whether the move is going towards the other end.
  forward: ->
    return true if @queen
    (@target[Y] - @cons[Y]) == @direction()

  diagonals: (max_length = 1) ->
    _.chain([[-1, 1], [1, 1], [-1, -1], [1, -1]]).map((vec) =>
      tiles   = []
      length  = 1
      while length <= max_length
        cons = [@cons[X] + vec[X]*length, @cons[Y] + vec[Y]*length]
        length++

        break unless bound(cons)
        tiles.push cons
      return undefined if tiles.length == 0
      [tiles, vec]
    ).compact().value()

  UNABLE = 2
  DONE   = 1
  WRONG  = 0

  find: (length, color) ->
    # Looks for the [x,*,*] in diagonal '   x**' where x is the other checker.
    plausible_diognals = _(@diagonals(length)).map ([[tiles..., last], vec]) =>
      plausible = null
      tiles = _(tiles).select (tile) =>
        piece      = @set.get(tile)
        plausible ?= piece && piece.color == color

      if tiles.length == 0
        null # removed by compatct
      else
        tiles.push last
        [tiles, vec]

    _(plausible_diognals).compact()

  # Did he do the obligatory attacking?
  attacked: (dry_run = false) ->
    plausible_diognals = @find((if @queen then Infinity else 2), !@color)

    empties  = []
    attacked = _(plausible_diognals).any ([tiles, vec]) =>
      past_empty = null # Am I trying to search for empty spaces after a piece?

      _(_(tiles).tail()).detect (tile) =>
        piece = @set.get(tile)
        empties.push(empty = not past_empty and not piece)
        past_empty ?= piece && piece.color != @color # Dry run if past_empty.

        if !dry_run && empty && _.isEqual(tile, @target)
          @victim = @set.get(_(tiles).head())
          unless past_empty # Dry run if past empty.
            return true

    return DONE if attacked
    return UNABLE unless _(empties).any(false)
    return WRONG

  # synonym to «can attack»; independent of @target
  voltage: ->
    @attacked(true) != UNABLE

  valid: (cons) ->
    [@x, @y] = (@target = cons)
    required = []
    attacked = null
    required.push 'not self', ->
      not _.isEqual(@target, @cons)

    required.push 'proper square', ->
      @black() and @bound()

    required.push 'on diognals', ->
      @diagonal()

    required.push 'has attacked', ->
      (attacked = @attacked()) != WRONG

    required.push 'move forward and on empty tile', ->
      attacked != UNABLE or @forward() and @empty()

    while required.length
      [name, rule] = required.slice(0, 2)
      required.shift() && required.shift()

      if (state = rule.call(this))
        $.log "Rule '#{ name }' passed."
      else
        $.log "Rule '#{ name }' failed!"
        return state

    return true

  move: (cons) ->
    @victim = EMPTY
    type    = 'move'
    promote = (y, col) =>
      cons[Y] == y and @color == col

    if valid = @valid(cons)
      @queen = QUEEN if promote(0, WHITE) or promote(7, BLACK)
      if @victim?
        type = 'attack'
        @set.remove(@victim)

    return {valid: valid, type: type}

class Piece extends Rules
  constructor: (@cons, @color, @queen, @set) ->
    @element()

  piece = $("<div class='piece' />")

  element = ->
    @element = piece.clone(true).appendTo(Checkers.field)
  element: element

  classify: ->
    klass = ['piece']
    cons  = @cons
    cons  = flip(cons) unless @set.first
    klass.push "p#{ "hgfedcba"[cons[X]] }"
    klass.push "p#{ cons[Y] + 1 }"
    if @color == undefined
      klass.push 'ghost'
    else
      klass.push "#{ if @color == WHITE then 'white' else 'black' }"
    klass.push "#{ if @queen then 'queen' else '' }"
    klass.push "selected" if @selected
    @element.attr('class', klass.join(' '))

  render: ->
    @element = element() unless @element.is("html *")
    @classify()

  select: (value = null) ->
    # Holy balls, javascript allows this without initialization.
    @selected = value ? (@selected ^ 1)
    @render()

  is: (args...) ->
    @element.is(args...)

  hilight: ->
    @element.addClass('hilight')

  terminate: ->
    @element.remove()

class Pieces
  array: []
  constructor: ->
    @array = _(@array).clone()
    for x in [0..7]
      @array.push([])
      for y in [0..7]
        _(@array).last().push(EMPTY)

  create: ->
    for x in [0..7]
      for y in [0..5]
        if Rules.black([x, y])
          y += 2 if y > 2
          @new([x, y], (if y > 3 then WHITE else BLACK), REGULAR)

  new: (args...) ->
    [[x, y], _...] = args
    @array[x][y] = new Piece(args..., this)

  state: (value = null) ->
    if value
      @array = value
      for x in [0..7]
        for y in [0..7]
          if (piece = @array[x][y])
            piece.cons = [x, y]
    else
      # Manual deep clone. haha!
      _.chain(@array).clone().map((a) -> _(a).clone()).value()

  remove: (p) ->
    @array[p.cons[X]][p.cons[Y]].terminate()
    @array[p.cons[X]][p.cons[Y]] = EMPTY

  lookup: (cons) ->
    @get(cons, true)

  get: (cons, silent) ->
    try
      @array[cons[X]][cons[Y]]
    catch e
      unless silent
        $.log "Error on requesting #{ cons[X] }x#{ cons[Y] } from piece set."
        throw e

  list: (fun) ->
    _.chain(@array).flatten().compact().value()

  render: ->
    _(@list()).invoke('render')

  find: (fun = null) ->
    if fun && (target = fun).nodeName
      fun = (p) -> p.is(target)
    fun = fun || (p) -> p.is('.selected')
    ret = undefined

    _(@list()).each (p) ->
      ret = p if fun(p)

    ret

  voltages: (color) ->
    fun = (p) ->
      !!p.color == !!color and p.voltage()

    _(@list()).select(fun)

  move: (piece, cons) ->
    # A check of emptiness of the destination could be placed here.
    if (moved = piece.move(cons))['valid']
      @array[cons[X]][cons[Y]] = piece
      @array[piece.cons[X]][piece.cons[Y]] = null
      piece.cons = cons

    return moved

class Moves # saves moves to jump back to.
  constructor: (@pieces) ->
    @clear()

  add: (cons, state) ->
    ghost = new Piece(cons, undefined, REGULAR, @pieces)
    ghost.render()
    @positions.push [ghost, state]

  rollback: (cons) ->
    if (move = _(@positions).last())
      [ghost, state] = move

      if true # FIXME: ghost == piece from pieces from cons
        [ghost, state] = @positions.pop()
        @pieces.state(state)
        @pieces.render()
        ghost.terminate()

  clear: ->
    if @positions and @positions.length > 0
      _(@positions).each ([ghost, _]) ->
        ghost.terminate()

    # position = [[ghost, state], ...]
    # state doesn't have ghosts in it.
    @positions = []

class Board
  unit: null # pixels per one square
  turn: WHITE

  constructor: ->
    @pieces = new Pieces
    @moves  = new Moves(@pieces)

  create: ->
    @first = @turn == WHITE and not @frozen
    @pieces.first = @first
    @pieces.create(@first)

  delegate: (method, data) ->
    # IT'S OKAY, WE'LL JUST WHITELIST IT AND IT BE SECURE.
    white = method.match /^release|correct|pick$/
    return unless white
    this[method](data)

  correct: (cons) ->
    @moves.rollback(@pieces.get(cons))

  deselect: ->
    @pieces.find()?.select() # Deselect if needed.

  pick: (cons) ->
    @deselect()
    target = @pieces.lookup(cons)

    if target and !!@turn == !!target.color
      target.select()

  # Allowed to move.
  allowed: (piece, cons) ->
    can = true
    can = can and piece
    can = can and !!@turn == !!piece.color

    voltaged  = @pieces.voltages(@turn)
    must_move = _.isEmpty(voltaged) or _(voltaged).contains(piece)
    _(voltaged).invoke('hilight') if can and !must_move
    can = can and must_move
    can

  find: (cons) ->
    sel       = null
    plausible = _(@pieces.list()).select (piece) =>
      return unless @allowed(piece, cons)
      return unless piece.valid(cons)
      sel = piece if piece.selected
      true

    return sel if sel
    plausible[0] if plausible.length == 1

  release: (cons) => # Release can be anywhere.
    sel = @find(cons)

    return unless sel

    from       = sel.cons
    last_state = @pieces.state()
    valid      = (move = @pieces.move(sel, cons))['valid']
    @put(sel, from, last_state, move['type']) if valid

  put: (piece, from, last_state, type) -> # Put only where cons are valid.
    if type == 'attack' and piece.voltage()
      @moves.add(from, last_state)
    else
      @moves.clear()
      @deselect()
      @turn   ^= true
      @frozen ^= true
    @render()

  won: ->
    uni = _.chain(@pieces.list()).flatten().compact().pluck('color').uniq().value()
    return if uni.length != 1
    uni[0]

  clear: ->
    if @pieces
      _.chain(@pieces.list()).compact().invoke('terminate')

  render: ->
    'wat'

class Board_h extends Board
  coord: (e) ->
    [x, y] = [e.originalEvent.layerX, e.originalEvent.layerY]
    cons = [Math.floor(x / @unit), Math.floor(y / @unit)]
    cons = flip(cons) unless @first
    cons

  constructor: (@field, @unit) ->
    super

    @field.off('click')
    @field.
      on('click',           (e) => @send('release', e)).
      on('click', '.ghost', (e) => @send('correct', e)).
      on('click', '.piece', (e) => @send('pick', e))

    Game.dispacher.route 'untrustable.data', (data) =>
      @delegate(data.method, data.cons) if @frozen

  # Hey there mouse clicks, c'mere you!
  send: (method, e) ->
    e.stopPropagation()
    cons = @pieces.find(e.target)?.cons || @coord(e)

    return if @frozen
    @delegate(method, cons)
    Game.dispacher.send { type: 'untrustable.data', \
      method: method, cons: cons
    }

  finish: (color) ->
    # Game has ended.
    if @first == color
      text = 'You won!'
    else
      text = 'The other party won.'
    Game.console.log(text)
    @field.addClass('finish')
    Checkers.restart()

  delegate: (args...) ->
    super(args...)

    @finish(color) unless (color = @won()) == undefined

  render: ->
    @field.removeClass('whites-turn blacks-turn warm finish')
    @field.addClass("#{ if !!@turn == !!WHITE then 'white' else 'black' }s-turn")
    @field.addClass("warm") unless @frozen
    @pieces.render()

Game.list.russian_checkers = Checkers =
  init: (@container) ->
    @container.addClass('checkers')
    @field = $("<div />").appendTo(@container)
    @field.addClass('checkers dimmensional')
    Game.dispacher.route 'dice.roll', (data) =>
      # Gentlemen don't cheat!
      @stop()
      @new()
      @board.frozen = @rand > parseFloat(data['roll'])
      @board.create()
      @board.render()

  new: ->
    @board = new Board_h(@field, @field.width() / 8)

  start: ->
    Game.dispacher.send {type: 'dice.roll', roll: (@rand = Math.random())}

  stop: ->
    @board?.clear()
    @board = null

  restart: ->
    fun = =>
      @start()

    setTimeout(fun, 2500)
