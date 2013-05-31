use inc::Module::Package 'RDF:tobyink 0.012';

dynamic_config;
requires Moo => "1.002000" unless eval 'use Moose 2.00; 1' || eval 'use Mouse 1.00; 1';
