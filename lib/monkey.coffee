MonkeyView = require './monkey-view'
$ = require 'jquery'

exec = require('child_process').exec
spawn = require('child_process').spawn
os = require('os')

{CompositeDisposable} = require 'atom'

module.exports = Monkey =
    config:
        monkey2Path:
            title: 'Monkey2 Path'
            description: 'The path to your installation of Monkey2'
            type: 'string'
            default: ''
        showOutputOnBuild:
            title: 'Automatically show output on build'
            type: 'boolean'
            default: true

    monkeyViewState: null
    modalPanel: null
    subscriptions: null
    compilationTarget: ''
    projects: {}
    projectNamespace: ''

    activate: (state) ->
        self = this
        @monkeyViewState = new MonkeyView(state.monkeyViewState)
        @panel = atom.workspace.addBottomPanel(item: @monkeyViewState.getElement(), visible: true)
        @outputPanel = atom.workspace.addBottomPanel(item: @monkeyViewState.getOutput(), visible: false)

        # Enable view event handlers
        $(@monkeyViewState.playBtn).on 'click', (event) =>
            target = @getCompilationTarget()
            if target != undefined and target != ''
                @buildDefault()
            else
                @buildCurrent()

        $(@monkeyViewState.toggleBtn).on 'click', (event) =>
            if @outputPanel.isVisible()
                @outputPanel.hide()
                @monkeyViewState.hideOutput()
            else
                @outputPanel.show()
                @monkeyViewState.showOutput()

        $(@monkeyViewState.clearBtn).on 'click', (event) =>
            @monkeyViewState.clearOutput()


        # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
        @subscriptions = new CompositeDisposable

        @subscriptions.add atom.commands.add 'atom-workspace',
            'monkey:build': => @build(self.getCompilationTarget())

        @subscriptions.add atom.commands.add 'atom-workspace',
            'monkey:buildDefault': => @buildDefault()

        @subscriptions.add atom.commands.add 'atom-workspace',
            'monkey:buildCurrent': => @buildCurrent()

        @subscriptions.add atom.commands.add 'atom-workspace',
            'monkey:hideOutput': => @hideOutput()

        @subscriptions.add atom.commands.add 'atom-workspace',
            'monkey:toggleOutput': => @toggleOutput()

        @subscriptions.add atom.commands.add '.file.selected',
            'monkey:setCompilationTarget': (event) ->
                self.setCompilationTarget(event.target)

        @subscriptions.add atom.commands.add '.file.selected',
            'monkey:buildSelected': (event) ->
                self.build(event.target.getAttribute('data-path'))

        @projectNamespace = atom.project.getPaths()[0]
        @projects = state.projects

        if @projects != null and @projects != undefined and @projects[@projectNamespace] != undefined

            compilationTarget = @projects[@projectNamespace].compilationTarget

            if compilationTarget != undefined
                pathToSearch = '[data-path="'+compilationTarget+'"]'
                fileNodes = document.querySelectorAll('.name.icon-file-text')
                fileNode = (item for item in fileNodes when item.getAttribute('data-path') == compilationTarget).pop()
                this.setCompilationTarget(fileNode)
            console.log("restored serialized state")
        else
            @projects = {}
            @projects[@projectNamespace] = ''
            @projects[@projectNamespace].compilationTarget = ''
            console.log "fresh projects state"

    deactivate: ->
        @subscriptions.dispose()
        @monkeyViewState.destroy()

    serialize: ->
        monkeyViewState: @monkeyViewState.serialize()
        projects: @projects

    setCompilationTarget: (fileNode)->
        #check for existing compilationTarget; remove styling if found
        ctNode = document.getElementById("compilationTarget")
        if ctNode != null
            ctNode.id = ''
            ctNode.classList.remove('icon-arrow-right')
            ctNode.classList.add('icon-file-text')

        #add green arrow styling
        fileNode.classList.remove('icon-file-text')
        fileNode.classList.add('icon-arrow-right')
        fileNode.id = "compilationTarget"

        #save a copy of the file path to the project so we can serialize it
        @projects[@projectNamespace] =
            compilationTarget : fileNode.getAttribute('data-path')

    getCompilationTarget: ->
        @projects[@projectNamespace].compilationTarget

    hideOutput: ->
        @outputPanel.hide()

    showOutput: ->
        @outputPanel.show()

    toggleOutput: ->
        if @outputPanel.isVisible() then @outputPanel.hide() else @outputPanel.show()

    buildCurrent: ->
        @build(atom.workspace.getActiveTextEditor().getPath())

    buildDefault: ->
        target = @getCompilationTarget()
        if target == null
            atom.notifications.addError("No compilation target set. Right click a monkey file in the folder tree and choose 'Set Compilation Target'")
            return false
        else
            this.build(target)

    build: (targetPath) ->
        extension = targetPath.substr(targetPath.lastIndexOf('.')+1)
        mPath = ''
        buildOut = null

        if extension == 'monkey2'
            mPath = atom.config.get "language-monkey2.monkey2Path"
            if mPath == '' or mPath == null or mPath == undefined
                atom.notifications.addError("The path to Monkey2 needs to be set in the package settings")
                return
            if os.platform() == 'win32'
                mPath += "\\bin\\mx2cc_windows.exe"
            else if os.platform() == 'darwin'
                mPath += "/bin/mx2cc_macos"
            else
                mPath += "/bin/mx2cc_linux"
            options = @monkeyViewState.getOptions()
            buildOut = spawn mPath, ['makeapp', '-'+options.action, '-target='+options.target, '-config='+options.config, '-apptype='+options.appType, targetPath]
            @monkeyViewState.clearOutput()

            if atom.config.get "language-monkey2.showOutputOnBuild"
                @showOutput()

        buildOut.stdout.on 'data', (data) =>
            message = data.toString().trim()
            errorRegex = /error/gi
            runningRegex = /Running/
            @monkeyViewState.outputMessage(message)

        buildOut.stderr.on 'data', (data) ->
            message = data.toString().trim()
            atom.notifications.addError(message)
