require! \gulp
require! \gulp-nodemon

gulp.task \dev:server, ->
    gulp-nodemon do
        exec-map: ls: \lsc
        ext: \ls
        ignore: <[gulpfile.ls README.md *.sublime-project public/*]>
        script: \./server.ls


gulp.task \default, <[dev:server]>