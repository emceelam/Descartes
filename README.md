# SYNOPSIS

make\_slippy\_map.pl \[FILE\]...

make\_slippy\_map.pl directory\_of\_graphic\_files

## DESCRIPTION

This program will take a hi-res graphics file (pdf, png, gif or jpg) and
generate a slippy map, also known
as google style map. If given a directory of graphics files, the generator will
generate a web page gallery of slippy maps.

You can see some examples at [http://sjsutech.com/](http://sjsutech.com/)

Perl module is available at [https://stratopan.com/emceelam/descartes/master](https://stratopan.com/emceelam/descartes/master)

Warning: This software is Alpha. This software works best on the
author's Linux laptop, and has no testing on anyone else's machine.

## ARGUMENTS

- --scale

    Sets the scale factors for the renders. For example, 75%, 100%, 125% and 150% is
    represented as 

        --scale=0.75,1,1.25,1.50

    Please, no spaces.

- --help

    Print this help section

- --quiet value

    Currently unimplemented

## BUGS

may fail on raster graphics of less than 2000x2000
