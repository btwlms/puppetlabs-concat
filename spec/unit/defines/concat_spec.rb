require 'spec_helper'

describe 'concat', :type => :define do

  shared_examples 'concat' do |title, params, id| 
    params = {} if params.nil?
    id = 'root' if id.nil?

    # default param values
    p = {
      :ensure           => 'present',
      :path             => title,
      :owner            => nil,
      :group            => nil,
      :mode             => '0644',
      :warn             => false,
      :force            => false,
      :show_diff        => true,
      :backup           => 'puppet',
      :backup_fragments => false,
      :replace          => true,
      :order            => 'alpha',
      :ensure_newline   => false,
      :validate_cmd     => nil,
    }.merge(params)

    safe_name            = title.gsub('/', '_')
    concatdir            = '/var/lib/puppet/concat'
    fragdir              = "#{concatdir}/#{safe_name}"
    concat_name          = 'fragments.concat.out'
    default_warn_message = '# This file is managed by Puppet. DO NOT EDIT.'

    let(:title) { title }
    let(:params) { params }
    let(:facts) do
      {
        :concat_basedir => concatdir,
        :id             => id,
        :osfamily       => 'Debian',
        :path           => '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
        :kernel         => 'Linux',
        :is_pe          => false,
      }
    end

    if p[:ensure] == 'present'
      it do
        should contain_file(fragdir).with({
          :ensure => 'directory',
          :mode   => '0750',
        })
      end

      it do
        should contain_file("#{fragdir}/fragments").with({
          :ensure  => 'directory',
          :mode    => '0750',
          :force   => true,
          :ignore  => ['.svn', '.git', '.gitignore'],
          :backup  => false,
          :purge   => true,
          :recurse => true,
        })
      end

      [
        "#{fragdir}/fragments.concat",
        "#{fragdir}/#{concat_name}",
      ].each do |file|
        it do
          should contain_file(file).with({
            :ensure => 'present',
            :mode   => '0640',
          })
        end
      end

      it do
        should contain_file(title).with({
          :ensure                  => 'present',
          :owner                   => p[:owner],
          :group                   => p[:group],
          :mode                    => p[:mode],
          :replace                 => p[:replace],
          :path                    => p[:path],
          :alias                   => "concat_#{title}",
          :source                  => "#{fragdir}/#{concat_name}",
          :validate_cmd            => p[:validate_cmd],
          :show_diff               => p[:show_diff],
          :backup                  => p[:backup],
          :selinux_ignore_defaults => p[:selinux_ignore_defaults],
          :selrange                => p[:selrange],
          :selrole                 => p[:selrole],
          :seltype                 => p[:seltype],
          :seluser                 => p[:seluser],
        })
      end

      cmd = "#{concatdir}/bin/concatfragments.rb " +
            "-o \"#{concatdir}/#{safe_name}/fragments.concat.out\" " +
            "-d \"#{concatdir}/#{safe_name}\""

      # flag order: fragdir, warnflag, forceflag, orderflag, newlineflag 
      if p.has_key?(:warn)
        case p[:warn]
        when TrueClass
          message = default_warn_message
        when 'true', 'yes', 'on'
          # should generate a stringified boolean warning
          message = default_warn_message
        when FalseClass
          message = nil
        when 'false', 'no', 'off'
          # should generate a stringified boolean warning
          message = nil
        else
          message = p[:warn]
        end

        unless message.nil?
          cmd += " -w \'#{message}\'"
        end
      end

      cmd += " -f" if p[:force]
      cmd += " -n" if p[:order] == 'numeric'
      cmd += " -l" if p[:ensure_newline] == true

      it do
        should contain_exec("concat_#{title}").with({
          :alias   => "concat_#{fragdir}",
          :command => cmd,
          :unless  => "#{cmd} -t",
        })
      end
    else
      [
        fragdir,
        "#{fragdir}/fragments",
        "#{fragdir}/fragments.concat",
        "#{fragdir}/#{concat_name}",
      ].each do |file|
        it do
          should contain_file(file).with({
            :ensure => 'absent',
            :force  => true,
          })
        end
      end

      it do
        should contain_file(title).with({
          :ensure => 'absent',
          :backup => p[:backup],
        })
      end

      it do
        should contain_exec("concat_#{title}").with({
          :alias   => "concat_#{fragdir}",
          :command => 'true',
          :unless  => 'true',
          :path    => '/bin:/usr/bin',
        })
      end
    end
  end

  context 'title' do
    context 'without path param' do
      # title/name is the default value for the path param. therefore, the
      # title must be an absolute path unless path is specified
      ['/foo', '/foo/bar', '/foo/bar/baz'].each do |title|
        context title do
          it_behaves_like 'concat', '/etc/foo.bar'
        end
      end

      ['./foo', 'foo', 'foo/bar'].each do |title|
        context title do
          let(:title) { title }
          it 'should fail' do
            expect { catalogue }.to raise_error(Puppet::Error, /is not an absolute path/)
          end
        end
      end
    end

    context 'with path param' do
      ['./foo', 'foo', 'foo/bar'].each do |title|
        context title do
          it_behaves_like 'concat', title, { :path => '/etc/foo.bar' }
        end
      end
    end
  end # title =>

  context 'as non-root user' do
    it_behaves_like 'concat', '/etc/foo.bar', {}, 'bob'
  end

  context 'ensure =>' do
    ['present', 'absent'].each do |ens|
      context ens do
        it_behaves_like 'concat', '/etc/foo.bar', { :ensure => ens }
      end
    end

    context 'invalid' do
      let(:title) { '/etc/foo.bar' }
      let(:params) {{ :ensure => 'invalid' }}
      it 'should fail' do
        expect { catalogue }.to raise_error(Puppet::Error, /#{Regexp.escape('does not match "^present$|^absent$"')}/)
      end
    end
  end # ensure =>

  context 'path =>' do
    context '/foo' do
      it_behaves_like 'concat', '/etc/foo.bar', { :path => '/foo' }
    end

    ['./foo', 'foo', 'foo/bar', false].each do |path|
      context path do
        let(:title) { '/etc/foo.bar' }
        let(:params) {{ :path => path }}
        it 'should fail' do
          expect { catalogue }.to raise_error(Puppet::Error, /is not an absolute path/)
        end
      end
    end
  end # path =>

  context 'owner =>' do
    context 'apenney' do
      it_behaves_like 'concat', '/etc/foo.bar', { :owner => 'apenny' }
    end

    context '1000' do
      it_behaves_like 'concat', '/etc/foo.bar', { :owner => 1000 }
    end

    context 'false' do
      let(:title) { '/etc/foo.bar' }
      let(:params) {{ :owner => false }}
      it 'should fail' do
        expect { catalogue }.to raise_error(Puppet::Error, /\$owner must be a string or integer/)
      end
    end
  end # owner =>

  context 'group =>' do
    context 'apenney' do
      it_behaves_like 'concat', '/etc/foo.bar', { :group => 'apenny' }
    end

    context '1000' do
      it_behaves_like 'concat', '/etc/foo.bar', { :group => 1000 }
    end

    context 'false' do
      let(:title) { '/etc/foo.bar' }
      let(:params) {{ :group => false }}
      it 'should fail' do
        expect { catalogue }.to raise_error(Puppet::Error, /\$group must be a string or integer/)
      end
    end
  end # group =>

  context 'mode =>' do
    context '1755' do
      it_behaves_like 'concat', '/etc/foo.bar', { :mode => '1755' }
    end

    context 'false' do
      let(:title) { '/etc/foo.bar' }
      let(:params) {{ :mode => false }}
      it 'should fail' do
        expect { catalogue }.to raise_error(Puppet::Error, /is not a string/)
      end
    end
  end # mode =>

  context 'warn =>' do
    [true, false, '# foo'].each do |warn|
      context warn do
        it_behaves_like 'concat', '/etc/foo.bar', { :warn => warn }
      end
    end

    context '(stringified boolean)' do
      ['true', 'yes', 'on', 'false', 'no', 'off'].each do |warn|
        context warn do
          it_behaves_like 'concat', '/etc/foo.bar', { :warn => warn }

          it 'should create a warning' do
            skip('rspec-puppet support for testing warning()')
          end
        end
      end
    end

    context '123' do
      let(:title) { '/etc/foo.bar' }
      let(:params) {{ :warn => 123 }}
      it 'should fail' do
        expect { catalogue }.to raise_error(Puppet::Error, /is not a string or boolean/)
      end
    end
  end # warn =>

  context 'force =>' do
    [true, false].each do |force|
      context force do
        it_behaves_like 'concat', '/etc/foo.bar', { :force => force }
      end
    end

    context '123' do
      let(:title) { '/etc/foo.bar' }
      let(:params) {{ :force => 123 }}
      it 'should fail' do
        expect { catalogue }.to raise_error(Puppet::Error, /is not a boolean/)
      end
    end
  end # force =>

  context 'show_diff =>' do
    [true, false].each do |show_diff|
      context show_diff do
        it_behaves_like 'concat', '/etc/foo.bar', { :show_diff => show_diff }
      end
    end

    context '123' do
      let(:title) { '/etc/foo.bar' }
      let(:params) {{ :show_diff => 123 }}
      it 'should fail' do
        expect { catalogue }.to raise_error(Puppet::Error, /is not a boolean/)
      end
    end
  end # show_diff =>

  context 'backup =>' do
    context 'reverse' do
      it_behaves_like 'concat', '/etc/foo.bar', { :backup => 'reverse' }
    end

    context 'false' do
      it_behaves_like 'concat', '/etc/foo.bar', { :backup => false }
    end

    context 'true' do
      it_behaves_like 'concat', '/etc/foo.bar', { :backup => true }
    end

    context 'true' do
      let(:title) { '/etc/foo.bar' }
      let(:params) {{ :backup => [] }}
      it 'should fail' do
        expect { catalogue }.to raise_error(Puppet::Error, /backup must be string or bool/)
      end
    end
  end # backup =>

  context 'backup_fragments =>' do
    context 'true' do
      it_behaves_like 'concat', '/etc/foo.bar', { :backup_fragments => true }
    end

    context 'false' do
      it_behaves_like 'concat', '/etc/foo.bar', { :backup_fragments => false }
    end

    context 'invalid' do
      let(:title) { '/etc/foo.bar' }
      let(:params) {{ :backup_fragments => "invalid" }}
      it 'should fail' do
        expect { catalogue }.to raise_error(Puppet::Error, /is not a boolean/)
      end
    end
  end # backup_fragments =>
  context 'replace =>' do
    [true, false].each do |replace|
      context replace do
        it_behaves_like 'concat', '/etc/foo.bar', { :replace => replace }
      end
    end

    context '123' do
      let(:title) { '/etc/foo.bar' }
      let(:params) {{ :replace => 123 }}
      it 'should fail' do
        expect { catalogue }.to raise_error(Puppet::Error, /is not a boolean/)
      end
    end
  end # replace =>

  context 'order =>' do
    ['alpha', 'numeric'].each do |order|
      context order do
        it_behaves_like 'concat', '/etc/foo.bar', { :order => order }
      end
    end

    context 'invalid' do
      let(:title) { '/etc/foo.bar' }
      let(:params) {{ :order => 'invalid' }}
      it 'should fail' do
        expect { catalogue }.to raise_error(Puppet::Error, /#{Regexp.escape('does not match "^alpha$|^numeric$"')}/)
      end
    end
  end # order =>

  context 'ensure_newline =>' do
    [true, false].each do |ensure_newline|
      context 'true' do
        it_behaves_like 'concat', '/etc/foo.bar', { :ensure_newline => ensure_newline}
      end
    end

    context '123' do
      let(:title) { '/etc/foo.bar' }
      let(:params) {{ :ensure_newline => 123 }}
      it 'should fail' do
        expect { catalogue }.to raise_error(Puppet::Error, /is not a boolean/)
      end
    end
  end # ensure_newline =>

  context 'validate_cmd =>' do
    if Puppet::Util::Package::versioncmp(Puppet::version, '3.5.0') > 0
      context '/usr/bin/test -e %' do
        it_behaves_like 'concat', '/etc/foo.bar', { :validate_cmd => '/usr/bin/test -e %' }
      end

      [ 1234, true ].each do |cmd|
        context cmd do
          let(:title) { '/etc/foo.bar' }
          let(:params) {{ :validate_cmd => cmd }}
          it 'should fail' do
            expect { catalogue }.to raise_error(Puppet::Error, /\$validate_cmd must be a string/)
          end
        end
      end
    end
  end # validate_cmd =>

  context 'selinux_ignore_defaults =>' do
    let(:title) { '/etc/foo.bar' }

    [true, false].each do |v|
      context v do
        it_behaves_like 'concat', '/etc/foo.bar', { :selinux_ignore_defaults => v }
      end
    end

    context '123' do
      let(:title) { '/etc/foo.bar' }
      let(:params) {{ :selinux_ignore_defaults => 123 }}
      it 'should fail' do
        expect { catalogue }.to raise_error(Puppet::Error, /is not a boolean/)
      end
    end
  end # selinux_ignore_defaults =>

  [
    :selrange,
    :selrole,
    :seltype,
    :seluser,
  ].each do |p|
    context " #{p} =>" do
      let(:title) { '/etc/foo.bar' }

      context 'foo' do
        it_behaves_like 'concat', '/etc/foo.bar', { p => 'foo' }
      end

      context 'false' do
        let(:title) { '/etc/foo.bar' }
        let(:params) {{ p => false }}
        it 'should fail' do
          expect { catalogue }.to raise_error(Puppet::Error, /is not a string/)
        end
      end
    end # #{p} =>
  end

  describe 'deprecated parameter' do
    context 'gnu =>' do
      context 'foo' do
        it_behaves_like 'concat', '/etc/foo.bar', { :gnu => 'foo'}

        it 'should create a warning' do
          skip('rspec-puppet support for testing warning()')
        end
      end
    end
  end

end

# vim:sw=2:ts=2:expandtab:textwidth=79
