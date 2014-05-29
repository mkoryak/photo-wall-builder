partition = require('linear-partitioning')
async = require('async')
fs = require('fs-extra')
path = require('path')
gm = require('gm')
glob = require('glob')
_ = require('underscore')

thumbWidth = 300 #TODO: should come from user input
thumbWidthPadding = 0
thumbQuality = 80
columnNum = 20
classes =
  ul: "column"
  li: "container"
  img: "thumb"

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
  parts = partition(heights, columnNum)

  ret = []
  _.each(parts, (list) ->
    col = []
    _.each(list, (h) ->
      col.push(map[h].pop())
    )
    ret.push(col)
  )
  return ret

fs.mkdirsSync(path.join(__dirname, 'input'))
fs.mkdirsSync(path.join(__dirname, 'output', 'thumbs'))
fs.mkdirsSync(path.join(__dirname, 'output', 'images'))

images = glob.sync(path.join(__dirname, 'input')+path.sep+"*.*") #get input images

if images.length > 0
  console.log("found #{images.length} images in input dir, starting work...")
else
  console.log("put some images into the 'input' dir to start doing some wall building!")
  return

async.auto(
  images: (cb) ->
    async.mapSeries(images, (image, cb) ->
      gm(image).size((err, size) ->
        if size
          basename = path.basename(image)
          thumb = path.join(__dirname, 'output', 'thumbs', basename)
          original = path.join(__dirname, 'output', 'images', basename)
          fs.copySync(image, original)
          cb(null, path: original, width: size.width, height: size.height, thumb: thumb, name: basename)
        else
          console.log('couldnt get size of image: ', image)
          cb(null, null)
      )
    , (err, images) ->
      cb(null, _.filter(images, (img) -> !!img))
    )
  makeThumbs: ["images", (cb, results) ->
    async.eachSeries(results.images, (obj, cb) ->
      if obj.width > obj.height
        width = thumbWidth
      else
        height = thumbWidth
      gm(obj.path).quality(thumbQuality).resize(width, height, ">").write(obj.thumb, (err) ->
        if err
          console.log("couldnt make thumb of: ", obj.path, err)
          obj.thumb = null
        cb()
      )
    , (err) ->
      cb(null, _.filter(results.images, (img) -> img.thumb))
    )
  ],
  partition: ['makeThumbs', (cb, results) ->
    cb(null, columnPartition(results.makeThumbs))
  ],
  render: ['partition', (cb, results) ->
    cols = results.partition
    wall = _.map(cols, (col) ->
      lis = _.map(col, (obj) ->
        return "\t\t<li class='#{classes.li}'><img src='/thumbs/#{obj.name}' class='#{classes.img}' data-orig='#{obj.name}'/></li>\n"
      ).join("\n")
      return "\t<ul class='#{classes.ul}'>\n#{lis}</ul>\n"
    ).join("\n\n")
    cb(null, """
<style>
img.#{classes.img} {
  width: #{thumbWidth}px;
}
div.photowall {
  width: #{columnNum * (thumbWidth + thumbWidthPadding)}px;
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