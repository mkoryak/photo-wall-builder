partition = require('linear-partitioning')
async = require('async')
fs = require('fs-extra')
path = require('path')
gm = require('gm')
glob = require('glob')
_ = require('underscore')
nunjucks = require('nunjucks')
staticServer = require('node-static')

module.exports = (options) ->


  log = ->
    if options.verbose
      console.log.apply(console.log, _.toArray(arguments))


  images = glob.sync(path.join(options.inputDir, options.imageGlob)) #get input images

  progress = ( ->
    total = images.length * 3
    cur = 0
    if options.verbose
      return (msg) ->
        cur++
        process.stdout.write(msg+": " + (100.0 * cur / total).toFixed(2) + "% \r")
    else
      return ->

  )()

  makePaths = (type) ->
    options[type].dir = path.normalize(options[type].dir.replace(/\\/g, "/")).replace(/^\/|\/$/g, '') #fix bad slahes, remove starting/ending slashes
    options[type].path = path.join(options.outputDir, options[type].dir)
    fs.mkdirsSync(options[type].path)

  columnPartition = ->
    return (cb, results) ->
      if images.length > 1000
        log("Calculating optimal column partitions, this might take a few minutes...")

      images = results.images
      heights = []
      map = {}
      _.each(images, (img) ->

        h = img.height / img.width
        heights.push(h)
        if not map[h]
          map[h] = []
        map[h].push(img)
      )
      parts = partition(heights, options.columnNum)

      ret = []
      maxHeight = -1
      _.each(parts, (list) ->
        col = []
        height = 0
        _.each(list, (h) ->
          img = map[h].pop()
          col.push(img)
          height += img.height / (img.width / options.thumb.maxWidth)
        )
        if height > maxHeight
          maxHeight = height
        if col.length
          ret.push(col)
      )
      cb(null, columns: ret, height: maxHeight)

  resizeImage = (obj, type, cb) ->
    opts = options[type]
    gm(obj.src).autoOrient().strip().quality(opts.quality).resize(opts.maxWidth, undefined, ">").write(obj[type], (err) ->
      if err
        log("couldnt make #{type} of: ", obj.src, err)
        obj[type] = null
      progress("Resizing Images")

      cb()
    )


  resizeImages = (type) -> #returns async friendly resize fn ;)
    return (cb, results) ->
      async.eachLimit(results.images, options.concurrency, (obj, cb) ->
        resizeImage(obj, type, cb)
      , (err) ->
        cb(null, _.filter(results.images, (img) -> img[type]))
      )

  #fun starts here...
  if options.startFresh
    fs.removeSync(options.outputDir)
  fs.mkdirsSync(options.inputDir)
  _.each(["original", "thumb"], makePaths)


  if images.length > 0
    log("Found #{images.length} images in input dir, starting to build wall...")
  else
    log("Put some images into the 'input' dir to start doing some wall building!")
    return

  async.auto(
    images: (cb) ->
      async.mapLimit(images, options.concurrency, (image, cb) ->
        fn = if options.useEXIFData then 'identify' else 'size'
        gm(image)[fn]((err, o) ->
          progress("Parsing Image Data")
          if o
            size = if options.useEXIFData then o.size else o
            basename = path.basename(image)
            cb(null,
              name: basename
              width: size.width
              height: size.height
              src: image,
              original: path.join(options.original.path, basename)
              thumb: path.join(options.thumb.path, basename)
              title: o['Profile-EXIF']?.Artist
              desc: o['Profile-EXIF']?['Image Description']
            )
          else
            log('couldnt get size of image (skipping it): ', image)
            cb(null, null)
        )
      , (err, images) ->

        cb(null, _.filter(images, (img) -> !!img))
      )
    makeThumbs:     ["images", resizeImages("thumb")]
    makeOriginals:  ["images", resizeImages("original")]
    partition:      ['images', columnPartition()]
    render:         ['partition', (cb, results) ->
      columns = results.partition.columns
      options.photowall =
        width: options.columnNum * (options.thumb.maxWidth + options.thumb.padding)
        height: ~~results.partition.height + 2

      wall = nunjucks.render(path.join('.', "templates", "photowall.html"), options: options, wall: columns)
      index = nunjucks.render(path.join('.', "templates", "index.html"), options: options, photowall: wall)
      fs.writeFileSync(path.join(options.outputDir, 'index.html'), index)
      log('')
      log('Generated the html, now waiting for the resizing to complete...')
      cb(null, index)
    ]
    finish:          ['render', 'makeOriginals', 'makeThumbs', (cb, results) ->
      log('')
      log('Images have all been generated. Wall is complete!')
      if options.server.listen
        server = new staticServer.Server(options.outputDir)
        require("http").createServer((request, response) ->
          request.addListener("end", ->
            server.serve(request, response)
          ).resume()
        ).listen(options.server.port, ->
          log("Wall preview server running at http://localhost:#{options.server.port}/")
        )
      cb()
    ]
  )