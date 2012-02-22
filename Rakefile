begin
  require 'bones'
rescue LoadError
  abort '### please install the "bones" gem ###'
end

task :default => 'test:run'
task 'gem:release' => 'test:run'

Bones do 
  name           'sundae'
  authors        'Don'
  email          'don@ohspite.net'
  url            'https://github.com/ohspite/sundae'
  summary        'Mix collections of files while maintaining complete separation.'
  description    'Mix collections of files while maintaining complete separation.'
  history_file   'CHANGELOG'
  manifest_file  'Manifest'
  readme_file    'README.rdoc'
  rdoc.main      'README.rdoc'

  ignore_file    '.gitignore'
  exclude        %w(tmp$ bak$ ~$ CVS \.svn/ \.git/ \.bzr/ \.bzrignore ^pkg/)
  rdoc.include   %w(README ^lib/ ^bin/ ^ext/ \.txt$ \.rdoc$)
  depend_on 'highline'
  depend_on 'configatron'
  depend_on 'rdoc'

#  spec.opts << '--color'
end
