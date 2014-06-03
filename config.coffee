path = require('path')

# Edit this file to change the default program settings
module.exports =
  original:
    maxWidth: 600
    quality: 95
    dir: "/images/originals/"
  thumb:
    maxWidth: 250
    padding: 0
    quality: 60
    dir: "/images/thumbs/"
  columnNum: 12
  lightbox:
    defaultTitle: "Photo Wall"
  startFresh: false #delete everything in the output dir before starting
  useEXIFData: false #get image title from the 'author' attribute and image desc from the 'description' attribute (makes program run much slower)
  concurrency: 4 #how many images to resize at once (more is not always better)
  outputDir: path.join(__dirname, "output")
  inputDir: path.join(__dirname, "input") #place where the pictures will live, but you have better control of finding them under this path using the 'imageGlob' option
  imageGlob: "*/**/*.*" #this globs every file in every dir under 'input' dir
  server:
    listen: true #start an http server in output dir for previewing output
    port: 42421
  verbose: true #log things to stdout

