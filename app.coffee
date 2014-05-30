partition = require('linear-partitioning')
async = require('async')
fs = require('fs-extra')
path = require('path')
gm = require('gm')
glob = require('glob')
_ = require('underscore')

options =
  original:
    maxWidth: 1200
    quality: 95
    dir: "/images/originals/"
  thumb:
    maxWidth: 200
    padding: 2
    quality: 85
    dir: "/images/thumbs/"
  columnNum: 15
  lightbox:
    title: "A Photo"
    footer: "The cat is cute"
  classes:
    ul: "list-unstyled pull-left"
    li: "brick"
    img: "thumb"
  startFresh: true

makePaths = (type) ->
  options[type].dir = path.normalize(options[type].dir.replace(/\\/g, "/")).replace(/^\/|\/$/g, '') #fix bad slahes, remove starting/ending slashes
  options[type].path = path.join(__dirname, "output", options[type].dir)
  fs.mkdirsSync(options[type].path)

columnPartition = (images) ->
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
    ret.push(col)
  )
  return ret

resizeImage = (obj, type, cb) ->
  opts = options[type]
  if obj.width > obj.height
    width = opts.maxWidth
  else
    height = opts.maxWidth
  gm(obj.src).quality(opts.quality).resize(width, height, ">").write(obj[type], (err) ->
    if err
      console.log("couldnt make #{type} of: ", obj.src, err)
      obj[type] = null
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

images = glob.sync(path.join(__dirname, 'input')+path.sep+"*.*") #get input images

if images.length > 0
  console.log("found #{images.length} images in input dir, getting the bricks out...")
else
  console.log("put some images into the 'input' dir to start doing some wall building!")
  return

async.auto(
  images: (cb) ->
    async.mapSeries(images, (image, cb) ->
      gm(image).size((err, size) ->
        if size
          basename = path.basename(image)
          cb(null,
            name: basename
            width: size.width
            height: size.height
            src: image,
            original: path.join(options.original.path, basename)
            thumb: path.join(options.thumb.path, basename)
          )
        else
          console.log('couldnt get size of image (skipping it): ', image)
          cb(null, null)
      )
    , (err, images) ->
      cb(null, _.filter(images, (img) -> !!img))
    )
  makeThumbs: ["images", resizeImages("thumb")],
  makeOriginals: ["images", resizeImages("original")],
  partition: ['makeThumbs', (cb, results) ->
    cb(null, columnPartition(results.makeThumbs))
  ],
  render: ['partition', (cb, results) ->
    cols = results.partition
    wall = _.map(cols, (col) ->
      lis = _.map(col, (obj) ->
        return """
    <li class='#{options.classes.li}'>
      <a href='/#{options.original.dir}/#{obj.name}' class='lightbox' data-title='#{options.lightbox.title}' data-footer='#{options.lightbox.footer}'>
        <img src='/#{options.thumb.dir}/#{obj.name}' class='#{options.classes.img}'/>
      </a>
    </li>"""
      ).join("")
      return "<ul class='#{options.classes.ul}'>\n#{lis}</ul>\n"
    ).join("\n\n")
    cb(null, """
<style type='text/css'>
img.#{options.classes.img.split(" ").join(".")} {
  width: #{options.thumb.maxWidth}px;
}
div.photowall {
  width: #{options.columnNum * (options.thumb.maxWidth + options.thumb.padding)}px;
}
</style>
<div class='photowall'>\n#{wall}</div>
""")
  ],
  build: ['render', (cb, results) ->
    html = results.render
    tpl = fs.readFileSync(path.join(__dirname, 'template.html')).toString()
    tpl = tpl.replace('###PHOTOWALL###', html)
    fs.writeFileSync(path.join(__dirname, 'output', 'index.html'), tpl)
    console.log('Photowall built! Look in the output dir for your wall')
    cb()
  ]
)