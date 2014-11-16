on_drop = (element, callback) ->
    
    $element = $(element)
    counter = 0

    update_counter = (num) ->
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

    detail = 512
    chunk = 32

    canvas = $('canvas')[0]
    canvas.width = data.length/detail

    context = canvas.getContext '2d'
    context.clearRect 0, 0, canvas.width, canvas.height
    context.translate 0, 256
    context.strokeStyle = 'rgba(0, 0, 0, 0.15)'

    index = 0

    interval = setInterval ->

        if index >= data.length
            clearInterval interval
            return

        context.beginPath()
        context.moveTo index/detail, (data[index-1] ? 0) * 256

        for a in [index .. index + detail * chunk]
            context.lineTo a/detail, data[a]*256

        index += detail * chunk

        context.stroke()

    , 0

$ ->

    window.audio_context = new AudioContext()

    on_drop '#drop-zone', (event) ->

        files = event.originalEvent.dataTransfer.files

        for file in files
            get_channel_data file, draw_waveform

        return undefined
