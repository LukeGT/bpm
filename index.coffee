on_drop = (element, callback) ->
    
    $element = $(element)
    counter = 0

    update_counter = (num) ->
        console.log num
        counter = num
        if counter > 0
            $element.addClass('dragover')
        else
            $element.removeClass('dragover')

    $element.on 'dragenter', (event) ->
        update_counter counter + 1
        $element.addClass('dragover')

    $element.on 'dragleave', (event) ->
        update_counter counter - 1

    $element.on 'dragover', (event) ->
        event.preventDefault()

    $element.on 'dragend', (event) ->
        update_counter 0

    $element.on 'drop', (event) ->
        event.preventDefault()
        update_counter 0
        callback.apply this, arguments

get_channel_data = (file, callback) ->
    
    reader = new FileReader()
    reader.readAsArrayBuffer(file)
    console.log 'loading file', file
    reader.onloadend = ->
        console.log 'decoding file', file
        window.audio_context.decodeAudioData reader.result, (buffer) ->
            console.log 'done'
            callback buffer.getChannelData(0)

draw_waveform = (data) ->

    detail = 2048

    context = $('canvas')[0].getContext '2d'
    context.translate 0, 256
    context.moveTo 0, 0

    for a in [0..1024*detail]
        context.lineTo a/detail, data[a]*256

    context.stroke()

$ ->

    window.audio_context = new AudioContext()

    on_drop '#drop-zone', (event) ->

        files = event.originalEvent.dataTransfer.files

        for file in files
            get_channel_data file, draw_waveform

        return undefined
