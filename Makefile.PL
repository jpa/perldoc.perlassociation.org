use strict;
use inc::Module::Install;

requires 'Moose';
requires 'MooseX::AttributeHelpers';
requires 'File::Find::Rule';
requires 'File::Path' => '2.07';
requires 'Pod::Xhtml';
requires 'local::lib';

WriteAll;