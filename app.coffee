partition = require('linear-partitioning')
async = require('async')
fs = require('fs-extra')
path = require('path')
gm = require('gm')
glob = require('glob')
_ = require('underscore')
nunjucks = require('nunjucks')

options =
  original:
    maxWidth: 600
    quality: 95
    dir: "/images/originals/"
  thumb:
    maxWidth: 75
    padding: 0
    quality: 60
    dir: "/images/thumbs/"
  columnNum: 25
  classes:
    ul: "list-unstyled pull-left"
    li: "brick"
    img: "thumb"
  startFresh: false
  imageGlob: "*.*"
  useEXIFData: true;

makePaths = (type) ->
  options[type].dir = path.normalize(options[type].dir.replace(/\\/g, "/")).replace(/^\/|\/$/g, '') #fix bad slahes, remove starting/ending slashes
  options[type].path = path.join(__dirname, "output", options[type].dir)
  fs.mkdirsSync(options[type].path)

columnPartition = ->
  return (cb, results) ->
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
    _.each(parts, (list) ->
      col = []
      _.each(list, (h) ->
        col.push(map[h].pop())
      )
      if col.length
        ret.push(col)
    )
    cb(null, ret)

resizeCount = 0
resizeImage = (obj, type, cb) ->
  opts = options[type]
  gm(obj.src).autoOrient().strip().quality(opts.quality).resize(opts.maxWidth, undefined, ">").write(obj[type], (err) ->
    if err
      console.log("couldnt make #{type} of: ", obj.src, err)
      obj[type] = null
    resizeCount++
    if resizeCount % 2 == 0
      process.stdout.write('.');

    cb()
  )


resizeImages = (type) -> #returns async friendly resize fn ;)
  return (cb, results) ->
    async.eachSeries(results.images, (obj, cb) ->
      resizeImage(obj, type, cb)
    , (err) ->
      cb(null, _.filter(results.images, (img) -> img[type]))
    )

#fun starts here...
if options.startFresh
  fs.removeSync(path.join(__dirname, "output"))
fs.mkdirsSync(path.join(__dirname, 'input'))
_.each(["original", "thumb"], makePaths)

images = glob.sync(path.join(__dirname, 'input', options.imageGlob)) #get input images

if images.length > 0
  console.log("found #{images.length} images in input dir, getting the bricks out...")
else
  console.log("put some images into the 'input' dir to start doing some wall building!")
  return

async.auto(
  images: (cb) ->
    async.mapSeries(images, (image, cb) ->
      fn = if options.useEXIFData then 'identify' else 'size'
      gm(image)[fn]((err, o) ->
        if o

          size = if options.useEXIFData then o.size else o
          basename = path.basename(image)
          process.stdout.write('.');
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
          console.log('couldnt get size of image (skipping it): ', image)
          cb(null, null)
      )
    , (err, images) ->

      cb(null, _.filter(images, (img) -> !!img))
    )
  makeThumbs:     ["images", resizeImages("thumb")]
  makeOriginals:  ["images", resizeImages("original")]
  partition:      ['images', columnPartition()]
  render:         ['partition', (cb, results) ->
    wall = nunjucks.render(path.join('.', "templates", "photowall.html"), options: options, wall: results.partition)
    index = nunjucks.render(path.join('.', "templates", "index.html"), options: options, photowall: wall)
    fs.writeFileSync(path.join(__dirname, 'output', 'index.html'), index)
    console.log('')
    console.log('Generated the html, now waiting for the resizing to complete...')
    cb(null, index)
  ]
  finish:          ['render', 'makeOriginals', 'makeThumbs', (cb, results) ->
    console.log('')
    console.log('Images have all been generated. Wall is complete!')
    cb()
  ]
)