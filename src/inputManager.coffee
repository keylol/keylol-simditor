
class InputManager extends Plugin

  opts:
    tabIndent: true

  constructor: (args...) ->
    super args...
    @editor = @widget

  _modifierKeys: [16, 17, 18, 91, 93]

  _arrowKeys: [37..40]

  _init: ->
    @_pasteArea = $('<div/>')
      .css({
        width: '1px',
        height: '1px',
        overflow: 'hidden',
        position: 'fixed',
        right: '0',
        bottom: '100px'
      })
      .attr({
        tabIndex: '-1',
        contentEditable: true
      })
      .addClass('simditor-paste-area')
      .appendTo(@editor.el)

    @editor.on 'valuechanged', =>
      # make sure each code block and img has a p following it
      @editor.body.find('pre, .simditor-image').each (i, el) =>
        $el = $(el)
        if ($el.parent().is('blockquote') or $el.parent()[0] == @editor.body[0]) and $el.next().length == 0
          $('<p/>').append(@editor.util.phBr)
            .insertAfter($el)

    @editor.body.on('keydown', $.proxy(@_onKeyDown, @))
      .on('keyup', $.proxy(@_onKeyUp, @))
      .on('mouseup', $.proxy(@_onMouseUp, @))
      .on('focus', $.proxy(@_onFocus, @))
      .on('blur', $.proxy(@_onBlur, @))
      .on('paste', $.proxy(@_onPaste, @))

    if @editor.textarea.attr 'autofocus'
      setTimeout =>
        @editor.body.focus()
      , 0

  _onFocus: (e) ->
    @editor.el.addClass('focus')
      .removeClass('error')
    @focused = true

    @editor.body.find('.selected').removeClass('selected')

    setTimeout =>
      @editor.trigger 'simditorfocus'
      @editor.trigger 'selectionchanged'
    , 0

  _onBlur: (e) ->
    @editor.el.removeClass 'focus'
    @editor.sync()
    @focused = false

    @editor.trigger 'simditorblur'

  _onMouseUp: (e) ->
    return if $(e.target).is('img, .simditor-image')
    @editor.trigger 'selectionchanged'

  _onKeyDown: (e) ->
    if @editor.triggerHandler(e) == false
      return false

    if e.which in @_modifierKeys or e.which in @_arrowKeys
      return

    metaKey = @editor.util.metaKey e
    $blockEl = @editor.util.closestBlockEl()

    # paste shortcut
    return if metaKey and e.which == 86

    # handle predefined shortcuts
    shortcutName = []
    shortcutName.push 'shift' if e.shiftKey
    shortcutName.push 'ctrl' if e.ctrlKey
    shortcutName.push 'alt' if e.altKey
    shortcutName.push 'cmd' if e.metaKey
    shortcutName.push e.which
    shortcutName = shortcutName.join '+'

    if @_shortcuts[shortcutName]
      @_shortcuts[shortcutName].call(this, e)
      return false

    # Check the condictional handlers
    if e.which of @_inputHandlers
      result = null
      @editor.util.traverseUp (node) =>
        return unless node.nodeType == 1
        handler = @_inputHandlers[e.which]?[node.tagName.toLowerCase()]
        result = handler?.call(@, e, $(node))
        !result
      if result
        @editor.trigger 'valuechanged'
        @editor.trigger 'selectionchanged'
        return false

    # safari doesn't support shift + enter default behavior
    if @editor.util.browser.safari and e.which == 13 and e.shiftKey
      $br = $('<br/>')

      if @editor.selection.rangeAtEndOf $blockEl
        @editor.selection.insertNode $br
        @editor.selection.insertNode $('<br/>')
        @editor.selection.setRangeBefore $br
      else
        @editor.selection.insertNode $br

      @editor.trigger 'valuechanged'
      @editor.trigger 'selectionchanged'
      return false

    # Remove hr node
    if e.which == 8
      $prevBlockEl = $blockEl.prev()
      if $prevBlockEl.is 'hr' and @editor.selection.rangeAtStartOf $blockEl
        # TODO: need to test on IE
        $prevBlockEl.remove()
        @editor.trigger 'valuechanged'
        @editor.trigger 'selectionchanged'
        return false

    # Tab to indent
    if e.which == 9 and (@opts.tabIndent or $blockEl.is 'pre') and !$blockEl.is('li')
      spaces = if $blockEl.is 'pre' then '\u00A0\u00A0' else '\u00A0\u00A0\u00A0\u00A0'
      spaceNode = document.createTextNode spaces
      @editor.selection.insertNode spaceNode
      @editor.trigger 'valuechanged'
      @editor.trigger 'selectionchanged'
      return false

    if @_typing
      clearTimeout @_typing if @_typing != true
      @_typing = setTimeout =>
        @editor.trigger 'valuechanged'
        @editor.trigger 'selectionchanged'
        @_typing = false
      , 200
    else
      setTimeout =>
        @editor.trigger 'valuechanged'
        @editor.trigger 'selectionchanged'
      , 10
      @_typing = true

    null

  _onKeyUp: (e) ->
    if @editor.triggerHandler(e) == false
      return false

    if e.which in @_arrowKeys
      @editor.trigger 'selectionchanged'
      return

    if e.which == 8 and @editor.body.is ':empty'
      p = $('<p/>').append(@editor.util.phBr)
        .appendTo(@editor.body)
      @editor.selection.setRangeAtStartOf p
      return

  _onPaste: (e) ->
    if @editor.triggerHandler(e) == false
      return false

    $blockEl = @editor.util.closestBlockEl()
    codePaste = $blockEl.is 'pre'
    @editor.selection.deleteRangeContents()
    @editor.selection.save()

    @_pasteArea.focus()

    setTimeout =>
      if @_pasteArea.is(':empty')
        pasteContent = null
      else if codePaste
        pasteContent = @editor.formatter.clearHtml @_pasteArea.html()
      else
        pasteContent = $('<div/>').append(@_pasteArea.contents())
        @editor.formatter.format pasteContent
        @editor.formatter.decorate pasteContent
        pasteContent = pasteContent.contents()

      @_pasteArea.empty()
      range = @editor.selection.restore()

      if !pasteContent
        return
      else if codePaste
        node = document.createTextNode(pasteContent)
        @editor.selection.insertNode node, range
      else if pasteContent.length < 1
        return
      else if pasteContent.length == 1 and pasteContent.is('p')
        children = pasteContent.contents()
        range.insertNode node for node in children
        @editor.selection.setRangeAfter children.last()
      else
        $blockEl = $blockEl.parent() if $blockEl.is 'li'

        if @editor.selection.rangeAtStartOf($blockEl, range)
          insertPosition = 'before'
        else if @editor.selection.rangeAtEndOf($blockEl, range)
          insertPosition = 'after'
        else
          @editor.selection.breakBlockEl($blockEl, range)
          insertPosition = 'before'

        $blockEl[insertPosition](pasteContent)
        @editor.selection.setRangeAtEndOf(pasteContent.last(), range)

      @editor.trigger 'valuechanged'
      @editor.trigger 'selectionchanged'
    , 10

  _inputHandlers:
    13: # enter

      # press enter in a empty list item
      li: (e, $node) ->
        return unless @editor.util.isEmptyNode $node
        e.preventDefault()
        range = @editor.selection.getRange()

        if !$node.next('li').length
          listEl = $node.parent()
          newBlockEl = $('<p/>').append(@editor.util.phBr).insertAfter(listEl)

          if $node.siblings('li').length
            $node.remove()
          else
            listEl.remove()

          range.setEnd(newBlockEl[0], 0)
        else
          newLi = $('<li/>').append(@editor.util.phBr).insertAfter($node)
          range.setEnd(newLi[0], 0)

        range.collapse(false)
        @editor.selection.selectRange(range)
        true

      # press enter in a code block: insert \n instead of br
      pre: (e, $node) ->
        e.preventDefault()
        range = @editor.selection.getRange()
        breakNode = null

        range.deleteContents()

        if !@editor.util.browser.msie && @editor.selection.rangeAtEndOf $node
          breakNode = document.createTextNode('\n\n')
          range.insertNode breakNode
          range.setEnd breakNode, 1
        else
          breakNode = document.createTextNode('\n')
          range.insertNode breakNode
          range.setStartAfter breakNode

        range.collapse(false)
        @editor.selection.selectRange range
        true

      # press enter in the last paragraph of blockquote, just leave the block quote
      blockquote: (e, $node) ->
        $closestBlock = @editor.util.closestBlockEl()
        return unless $closestBlock.is('p') and !$closestBlock.next().length and @editor.util.isEmptyNode $closestBlock
        $node.after $closestBlock
        @editor.selection.setRangeAtStartOf $closestBlock
        true

    8: # backspace
      pre: (e, $node) ->
        return unless @editor.selection.rangeAtStartOf $node
        codeStr = $node.html().replace('\n', '<br/>')
        $newNode = $('<p/>').append(codeStr || @editor.util.phBr).insertAfter $node
        $node.remove()
        @editor.selection.setRangeAtStartOf $newNode
        true

      blockquote: (e, $node) ->
        return unless @editor.selection.rangeAtStartOf $node
        $firstChild = $node.children().first().unwrap()
        @editor.selection.setRangeAtStartOf $firstChild
        true

    9: #tab
      li: (e, $node) ->

        if e.shiftKey
          $parent = $node.parent()
          $parentLi = $parent.parent('li')
          return true if $parentLi.length < 0

          @editor.selection.save()

          if $node.next('li').length > 0
            $('<' + $parent[0].tagName + '/>')
              .append($node.nextAll('li'))
              .appendTo($node)

          $node.insertAfter $parentLi
          $parent.remove() if $parent.children('li').length < 1
          @editor.selection.restore()
        else
          $parentLi = $node.prev('li')
          return true if $parentLi.length < 1

          @editor.selection.save()
          tagName = $node.parent()[0].tagName
          $childList = $parentLi.children('ul, ol')

          if $childList.length > 0
            $childList.append $node
          else
            $('<' + tagName + '/>')
              .append($node)
              .appendTo($parentLi)

          @editor.selection.restore()

        true

  _shortcuts:
    # meta + enter: submit form
    'cmd+13': (e) ->
      @editor.el.closest('form')
        .find('button:submit')
        .click()

  addShortcut: (keys, handler) ->
    @_shortcuts[keys] = $.proxy(handler, this)


