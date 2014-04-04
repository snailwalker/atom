{React, div, span} = require 'reactionary'
{$$} = require 'space-pen'
{debounce} = require 'underscore-plus'

InputComponent = require './input-component'
SelectionComponent = require './selection-component'
CursorComponent = require './cursor-component'
CustomEventMixin = require './custom-event-mixin'
SubscriberMixin = require './subscriber-mixin'

DummyLineNode = $$(-> @div className: 'line', style: 'position: absolute; visibility: hidden;', => @span 'x')[0]
MeasureRange = document.createRange()
TextNodeFilter = { acceptNode: -> NodeFilter.FILTER_ACCEPT }

module.exports =
EditorCompont = React.createClass
  pendingScrollTop: null
  lastScrollTop: null

  statics: {DummyLineNode}

  mixins: [CustomEventMixin, SubscriberMixin]

  render: ->
    {fontSize, lineHeight, fontFamily} = @state
    {editor} = @props

    div className: 'editor react', tabIndex: -1, style: {fontSize, lineHeight, fontFamily},
      div className: 'scroll-view', ref: 'scrollView',
        InputComponent ref: 'hiddenInput', className: 'hidden-input', onInput: @onInput
        @renderScrollableContent()
      div className: 'vertical-scrollbar', ref: 'verticalScrollbar', onScroll: @onVerticalScroll,
        div outlet: 'verticalScrollbarContent', style: {height: editor.getScrollHeight()}

  renderScrollableContent: ->
    {editor} = @props
    height = editor.getScrollHeight()
    WebkitTransform = "translateY(#{-editor.getScrollTop()}px)"

    div className: 'scrollable-content', style: {height, WebkitTransform},
      @renderCursors()
      @renderVisibleLines()
      @renderUnderlayer()

  renderVisibleLines: ->
    {editor} = @props
    [startRow, endRow] = @getVisibleRowRange()
    lineHeightInPixels = editor.getLineHeight()
    precedingHeight = startRow * lineHeightInPixels
    followingHeight = (editor.getScreenLineCount() - endRow) * lineHeightInPixels

    div className: 'lines', ref: 'lines', [
      div className: 'spacer', key: 'top-spacer', style: {height: precedingHeight}
      (for tokenizedLine in @props.editor.linesForScreenRows(startRow, endRow - 1)
        LineComponent({tokenizedLine, key: tokenizedLine.id}))...
      div className: 'spacer', key: 'bottom-spacer', style: {height: followingHeight}
    ]

  renderCursors: ->
    {editor} = @props

    for selection in editor.getSelections() when editor.selectionIntersectsVisibleRowRange(selection)
      CursorComponent(cursor: selection.cursor)

  renderUnderlayer: ->
    {editor} = @props

    div className: 'underlayer',
      for selection in editor.getSelections() when editor.selectionIntersectsVisibleRowRange(selection)
        SelectionComponent({selection})

  getVisibleRowRange: ->
    visibleRowRange = @props.editor.getVisibleRowRange()
    if @visibleRowOverrides?
      visibleRowRange[0] = Math.min(visibleRowRange[0], @visibleRowOverrides[0])
      visibleRowRange[1] = Math.max(visibleRowRange[1], @visibleRowOverrides[1])
    visibleRowRange

  getInitialState: -> {}

  getDefaultProps: -> updateSync: true

  componentDidMount: ->
    @measuredLines = new WeakSet

    @listenForDOMEvents()
    @listenForCustomEvents()
    @observeEditor()
    @observeConfig()

    @updateAllDimensions()
    @props.editor.setVisible(true)

  componentWillUnmount: ->
    @getDOMNode().removeEventListener 'mousewheel', @onMousewheel

  componentDidUpdate: ->
    @updateVerticalScrollbar()
    @measureNewLines()

  # The React-provided scrollTop property doesn't work in this case because when
  # initially rendering, the synthetic scrollHeight hasn't been computed yet.
  # trying to assign it before the element inside is tall enough?
  updateVerticalScrollbar: ->
    {editor} = @props
    scrollTop = editor.getScrollTop()

    return if scrollTop is @lastScrollTop

    scrollbarNode = @refs.verticalScrollbar.getDOMNode()
    scrollbarNode.scrollTop = scrollTop
    @lastScrollTop = scrollbarNode.scrollTop

  observeEditor: ->
    {editor} = @props
    @subscribe editor, 'screen-lines-changed', @onScreenLinesChanged
    @subscribe editor, 'selection-added', @onSelectionAdded
    @subscribe editor, 'selection-removed', @onSelectionAdded
    @subscribe editor.$scrollTop.changes, @requestUpdate
    @subscribe editor.$height.changes, @requestUpdate
    @subscribe editor.$width.changes, @requestUpdate
    @subscribe editor.$defaultCharWidth.changes, @requestUpdate
    @subscribe editor.$lineHeight.changes, @requestUpdate

  listenForDOMEvents: ->
    scrollViewNode = @refs.scrollView.getDOMNode()
    scrollViewNode.addEventListener 'mousewheel', @onMousewheel
    scrollViewNode.addEventListener 'overflowchanged', @onOverflowChanged
    @getDOMNode().addEventListener 'focus', @onFocus

  listenForCustomEvents: ->
    {editor, mini} = @props

    @addCustomEventListeners
      'core:move-left': => editor.moveCursorLeft()
      'core:move-right': => editor.moveCursorRight()
      'core:select-left': => editor.selectLeft()
      'core:select-right': => editor.selectRight()
      'core:select-all': => editor.selectAll()
      'core:backspace': => editor.backspace()
      'core:delete': => editor.delete()
      'core:undo': => editor.undo()
      'core:redo': => editor.redo()
      'core:cut': => editor.cutSelectedText()
      'core:copy': => editor.copySelectedText()
      'core:paste': => editor.pasteText()
      'editor:move-to-previous-word': => editor.moveCursorToPreviousWord()
      'editor:select-word': => editor.selectWord()
      # 'editor:consolidate-selections': (event) => @consolidateSelections(event)
      'editor:backspace-to-beginning-of-word': => editor.backspaceToBeginningOfWord()
      'editor:backspace-to-beginning-of-line': => editor.backspaceToBeginningOfLine()
      'editor:delete-to-end-of-word': => editor.deleteToEndOfWord()
      'editor:delete-line': => editor.deleteLine()
      'editor:cut-to-end-of-line': => editor.cutToEndOfLine()
      'editor:move-to-beginning-of-screen-line': => editor.moveCursorToBeginningOfScreenLine()
      'editor:move-to-beginning-of-line': => editor.moveCursorToBeginningOfLine()
      'editor:move-to-end-of-screen-line': => editor.moveCursorToEndOfScreenLine()
      'editor:move-to-end-of-line': => editor.moveCursorToEndOfLine()
      'editor:move-to-first-character-of-line': => editor.moveCursorToFirstCharacterOfLine()
      'editor:move-to-beginning-of-word': => editor.moveCursorToBeginningOfWord()
      'editor:move-to-end-of-word': => editor.moveCursorToEndOfWord()
      'editor:move-to-beginning-of-next-word': => editor.moveCursorToBeginningOfNextWord()
      'editor:move-to-previous-word-boundary': => editor.moveCursorToPreviousWordBoundary()
      'editor:move-to-next-word-boundary': => editor.moveCursorToNextWordBoundary()
      'editor:select-to-end-of-line': => editor.selectToEndOfLine()
      'editor:select-to-beginning-of-line': => editor.selectToBeginningOfLine()
      'editor:select-to-end-of-word': => editor.selectToEndOfWord()
      'editor:select-to-beginning-of-word': => editor.selectToBeginningOfWord()
      'editor:select-to-beginning-of-next-word': => editor.selectToBeginningOfNextWord()
      'editor:select-to-next-word-boundary': => editor.selectToNextWordBoundary()
      'editor:select-to-previous-word-boundary': => editor.selectToPreviousWordBoundary()
      'editor:select-to-first-character-of-line': => editor.selectToFirstCharacterOfLine()
      'editor:select-line': => editor.selectLine()
      'editor:transpose': => editor.transpose()
      'editor:upper-case': => editor.upperCase()
      'editor:lower-case': => editor.lowerCase()

    unless mini
      @addCustomEventListeners
        'core:move-up': => editor.moveCursorUp()
        'core:move-down': => editor.moveCursorDown()
        'core:move-to-top': => editor.moveCursorToTop()
        'core:move-to-bottom': => editor.moveCursorToBottom()
        'core:select-up': => editor.selectUp()
        'core:select-down': => editor.selectDown()
        'core:select-to-top': => editor.selectToTop()
        'core:select-to-bottom': => editor.selectToBottom()
        'editor:indent': => editor.indent()
        'editor:auto-indent': => editor.autoIndentSelectedRows()
        'editor:indent-selected-rows': => editor.indentSelectedRows()
        'editor:outdent-selected-rows': => editor.outdentSelectedRows()
        'editor:newline': => editor.insertNewline()
        'editor:newline-below': => editor.insertNewlineBelow()
        'editor:newline-above': => editor.insertNewlineAbove()
        'editor:add-selection-below': => editor.addSelectionBelow()
        'editor:add-selection-above': => editor.addSelectionAbove()
        'editor:split-selections-into-lines': => editor.splitSelectionsIntoLines()
        'editor:toggle-soft-tabs': => editor.toggleSoftTabs()
        'editor:toggle-soft-wrap': => editor.toggleSoftWrap()
        'editor:fold-all': => editor.foldAll()
        'editor:unfold-all': => editor.unfoldAll()
        'editor:fold-current-row': => editor.foldCurrentRow()
        'editor:unfold-current-row': => editor.unfoldCurrentRow()
        'editor:fold-selection': => neditor.foldSelectedLines()
        'editor:fold-at-indent-level-1': => editor.foldAllAtIndentLevel(0)
        'editor:fold-at-indent-level-2': => editor.foldAllAtIndentLevel(1)
        'editor:fold-at-indent-level-3': => editor.foldAllAtIndentLevel(2)
        'editor:fold-at-indent-level-4': => editor.foldAllAtIndentLevel(3)
        'editor:fold-at-indent-level-5': => editor.foldAllAtIndentLevel(4)
        'editor:fold-at-indent-level-6': => editor.foldAllAtIndentLevel(5)
        'editor:fold-at-indent-level-7': => editor.foldAllAtIndentLevel(6)
        'editor:fold-at-indent-level-8': => editor.foldAllAtIndentLevel(7)
        'editor:fold-at-indent-level-9': => editor.foldAllAtIndentLevel(8)
        'editor:toggle-line-comments': => editor.toggleLineCommentsInSelection()
        'editor:log-cursor-scope': => editor.logCursorScope()
        'editor:checkout-head-revision': => editor.checkoutHead()
        'editor:copy-path': => editor.copyPathToClipboard()
        'editor:move-line-up': => editor.moveLineUp()
        'editor:move-line-down': => editor.moveLineDown()
        'editor:duplicate-lines': => editor.duplicateLines()
        'editor:join-lines': => editor.joinLines()
        'editor:toggle-indent-guide': => atom.config.toggle('editor.showIndentGuide')
        'editor:toggle-line-numbers': =>  atom.config.toggle('editor.showLineNumbers')
        # 'core:page-down': => @pageDown()
        # 'core:page-up': => @pageUp()
        # 'editor:scroll-to-cursor': => @scrollToCursorPosition()

  observeConfig: ->
    @subscribe atom.config.observe 'editor.fontFamily', @setFontFamily

  setFontSize: (fontSize) ->
    @clearScopedCharWidths()
    @setState({fontSize})
    @updateLineDimensions()

  setLineHeight: (lineHeight) ->
    @setState({lineHeight})

  setFontFamily: (fontFamily) ->
    @clearScopedCharWidths()
    @setState({fontFamily})
    @updateLineDimensions()

  onFocus: ->
    @refs.hiddenInput.focus()

  onVerticalScroll: ->
    scrollTop = @refs.verticalScrollbar.getDOMNode().scrollTop
    return if @props.editor.getScrollTop() is scrollTop

    animationFramePending = @pendingScrollTop?
    @pendingScrollTop = scrollTop
    unless animationFramePending
      requestAnimationFrame =>
        @props.editor.setScrollTop(@pendingScrollTop)
        @pendingScrollTop = null

  onMousewheel: (event) ->
    # To preserve velocity scrolling, delay removal of the event's target until
    # after mousewheel events stop being fired. Removing the target before then
    # will cause scrolling to stop suddenly.
    @visibleRowOverrides = @getVisibleRowRange()
    @clearVisibleRowOverridesAfterDelay ?= debounce(@clearVisibleRowOverrides, 100)
    @clearVisibleRowOverridesAfterDelay()

    @refs.verticalScrollbar.getDOMNode().scrollTop -= event.wheelDeltaY
    event.preventDefault()

  clearVisibleRowOverrides: ->
    @visibleRowOverrides = null
    @forceUpdate()

  clearVisibleRowOverridesAfterDelay: null

  onOverflowChanged: ->
    @props.editor.setHeight(@refs.scrollView.getDOMNode().clientHeight)

  onInput: (char, replaceLastChar) ->
    @props.editor.insertText(char)

  onScreenLinesChanged: ({start, end}) ->
    {editor} = @props
    @requestUpdate() if editor.intersectsVisibleRowRange(start, end + 1) # TODO: Use closed-open intervals for change events

  onSelectionAdded: (selection) ->
    {editor} = @props
    @requestUpdate() if editor.selectionIntersectsVisibleRowRange(selection)

  onSelectionRemoved: (selection) ->
    {editor} = @props
    @requestUpdate() if editor.selectionIntersectsVisibleRowRange(selection)

  requestUpdate: ->
    @forceUpdate()

  updateAllDimensions: ->
    {height, width} = @measureScrollViewDimensions()
    {lineHeightInPixels, charWidth} = @measureLineDimensions()
    {editor} = @props

    editor.setHeight(height)
    editor.setWidth(width)
    editor.setLineHeight(lineHeightInPixels)
    editor.setDefaultCharWidth(charWidth)

  updateLineDimensions: ->
    {lineHeightInPixels, charWidth} = @measureLineDimensions()
    {editor} = @props

    editor.setLineHeight(lineHeightInPixels)
    editor.setDefaultCharWidth(charWidth)

  measureScrollViewDimensions: ->
    scrollViewNode = @refs.scrollView.getDOMNode()
    {height: scrollViewNode.clientHeight, width: scrollViewNode.clientWidth}

  measureLineDimensions: ->
    linesNode = @refs.lines.getDOMNode()
    linesNode.appendChild(DummyLineNode)
    lineHeightInPixels = DummyLineNode.getBoundingClientRect().height
    charWidth = DummyLineNode.firstChild.getBoundingClientRect().width
    linesNode.removeChild(DummyLineNode)
    {lineHeightInPixels, charWidth}

  measureNewLines: ->
    [visibleStartRow, visibleEndRow] = @getVisibleRowRange()
    linesNode = @refs.lines.getDOMNode()

    for tokenizedLine, i in @props.editor.linesForScreenRows(visibleStartRow, visibleEndRow - 1)
      unless @measuredLines.has(tokenizedLine)
        lineNode = linesNode.children[i + 1]
        @measureCharactersInLine(tokenizedLine, lineNode)

  measureCharactersInLine: (tokenizedLine, lineNode) ->
    {editor} = @props
    iterator = document.createNodeIterator(lineNode, NodeFilter.SHOW_TEXT, TextNodeFilter)

    for {value, scopes} in tokenizedLine.tokens
      textNode = iterator.nextNode()
      charWidths = editor.getScopedCharWidths(scopes)
      for char, i in value
        unless charWidths[char]?
          MeasureRange.setStart(textNode, i)
          MeasureRange.setEnd(textNode, i + 1)
          charWidth = MeasureRange.getBoundingClientRect().width
          editor.setScopedCharWidth(scopes, char, charWidth)

    @measuredLines.add(tokenizedLine)

  clearScopedCharWidths: ->
    @measuredLines.clear()
    @props.editor.clearScopedCharWidths()

LineComponent = React.createClass
  render: ->
    div className: 'line', dangerouslySetInnerHTML: {__html: @buildInnerHTML()}

  buildInnerHTML: ->
    if @props.tokenizedLine.text.length is 0
      "<span>&nbsp;</span>"
    else
      @buildScopeTreeHTML(@props.tokenizedLine.getScopeTree())

  buildScopeTreeHTML: (scopeTree) ->
    if scopeTree.children?
      html = "<span class='#{scopeTree.scope.replace(/\./g, ' ')}'>"
      html += @buildScopeTreeHTML(child) for child in scopeTree.children
      html += "</span>"
      html
    else
      "<span>#{scopeTree.getValueAsHtml({})}</span>"

  shouldComponentUpdate: -> false
