const binding = require('node-gyp-build')(__dirname)

exports.render = async (svg, options) => binding.render(svg, options)
