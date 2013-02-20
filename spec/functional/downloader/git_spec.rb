require File.expand_path('../../../spec_helper', __FILE__)

module Pod
  describe Downloader::Git do
    extend SpecHelper::TemporaryDirectory

    before do
      @pod = LocalPod.new(fixture_spec('banana-lib/BananaLib.podspec'), temporary_sandbox, Platform.ios)
    end

    it "checks out a specific commit" do
      @pod.top_specification.stubs(:source).returns(
        :git => fixture('banana-lib'), :commit => 'fd56054'
      )
      downloader = Downloader.for_pod(@pod)
      downloader.download

      (@pod.root + 'README').read.strip.should == 'first commit'
    end

    it "checks out a specific branch" do
      @pod.top_specification.stubs(:source).returns(
        :git => fixture('banana-lib'), :branch => 'topicbranch'
      )
      downloader = Downloader.for_pod(@pod)
      downloader.download

      (@pod.root + 'README').read.strip.should == 'topicbranch'
    end

    it "checks out a specific tag" do
      @pod.top_specification.stubs(:source).returns(
        :git => fixture('banana-lib'), :tag => 'v1.0'
      )
      downloader = Downloader.for_pod(@pod)
      downloader.download

      (@pod.root + 'README').read.strip.should == 'v1.0'
    end

    it "doesn't updates submodules by default" do
      @pod.top_specification.stubs(:source).returns(
        :git => fixture('banana-lib'), :commit => '6cc9afc'
      )
      downloader = Downloader.for_pod(@pod)
      downloader.download

      (@pod.root + 'README').read.strip.should == 'post v1.0'
      (@pod.root + 'libPusher/README.md').should.not.exist?
    end

    it "initializes submodules when checking out a specific commit" do
      @pod.top_specification.stubs(:source).returns(
        :git => fixture('banana-lib'), :commit => '6cc9afc', :submodules => true
      )
      downloader = Downloader.for_pod(@pod)
      downloader.download

      (@pod.root + 'README').read.strip.should == 'post v1.0'
      (@pod.root + 'libPusher/README.md').read.strip.should.match /^libPusher/
    end

    it "initializes submodules when checking out a specific tag" do
      @pod.top_specification.stubs(:source).returns(
        :git => fixture('banana-lib'), :tag => 'v1.1', :submodules => true
      )
      downloader = Downloader.for_pod(@pod)
      downloader.download

      (@pod.root + 'README').read.strip.should == 'post v1.0'
      (@pod.root + 'libPusher/README.md').read.strip.should.match /^libPusher/
    end

    it "prepares the cache if it does not exist" do
      @pod.top_specification.stubs(:source).returns(
        :git => fixture('banana-lib'), :commit => 'fd56054'
      )
      downloader = Downloader.for_pod(@pod)
      downloader.cache_path.rmtree if downloader.cache_path.exist?
      downloader.expects(:create_cache).once
      downloader.stubs(:download_commit)
      downloader.download
    end

    it "prepares the cache if it does not exist when the HEAD is requested explicitly" do
      @pod.top_specification.stubs(:source).returns(
        :git => fixture('banana-lib')
      )
      downloader = Downloader.for_pod(@pod)
      downloader.cache_path.rmtree if downloader.cache_path.exist?
      downloader.expects(:create_cache).once
      downloader.stubs(:clone)
      downloader.download_head
    end

    it "removes the oldest repo if the caches is too big" do
      @pod.top_specification.stubs(:source).returns(
        :git => fixture('banana-lib'), :commit => 'fd56054'
      )
      original_chace_size = Downloader::Git::MAX_CACHE_SIZE
      Downloader::Git.__send__(:remove_const,'MAX_CACHE_SIZE')
      Downloader::Git::MAX_CACHE_SIZE = 0
      downloader = Downloader.for_pod(@pod)
      downloader.stubs(:cache_dir).returns(temporary_directory)
      downloader.download
      downloader.cache_path.should.not.exist?
      Downloader::Git.__send__(:remove_const,'MAX_CACHE_SIZE')
      Downloader::Git::MAX_CACHE_SIZE = original_chace_size
    end

    it "raises if it can't find the url" do
      @pod.top_specification.stubs(:source).returns(
        :git => 'find_me_if_you_can'
      )
      downloader = Downloader.for_pod(@pod)
      lambda { downloader.download }.should.raise Informative
    end

    it "raises if it can't find a commit" do
      @pod.top_specification.stubs(:source).returns(
        :git => fixture('banana-lib'), :commit => 'aaaaaa'
      )
      downloader = Downloader.for_pod(@pod)
      lambda { downloader.download }.should.raise Informative
    end

    it "raises if it can't find a tag" do
      @pod.top_specification.stubs(:source).returns(
        :git => fixture('banana-lib'), :tag => 'aaaaaa'
      )
      downloader = Downloader.for_pod(@pod)
      lambda { downloader.download }.should.raise Informative
    end

    it "does not raise if it can find the reference" do
      @pod.top_specification.stubs(:source).returns(
        :git => fixture('banana-lib'), :commit => 'fd56054'
      )
      downloader = Downloader.for_pod(@pod)
      lambda { downloader.download }.should.not.raise
    end

    it "returns the cache directory as the clone url" do
      @pod.top_specification.stubs(:source).returns(
        :git => fixture('banana-lib'), :commit => 'fd56054'
      )
      downloader = Downloader.for_pod(@pod)
      downloader.clone_url.to_s.should.match /Library\/Caches\/CocoaPods\/Git/
    end

    it "updates the cache if the HEAD is requested" do
      @pod.top_specification.stubs(:source).returns(
        :git => fixture('banana-lib')
      )
      downloader = Downloader.for_pod(@pod)
      downloader.expects(:update_cache).once
      downloader.download
    end

    it "updates the cache if the ref is not available" do
      # create the origin repo and the cache
      tmp_repo_path = temporary_directory + 'banana-lib-source'
      `git clone #{fixture('banana-lib')} #{tmp_repo_path}`

      @pod.top_specification.stubs(:source).returns(
        :git => tmp_repo_path, :commit => 'fd56054'
      )
      downloader = Downloader.for_pod(@pod)
      downloader.download

      # make a new commit in the origin
      commit = ''
      Dir.chdir(tmp_repo_path) do
        `touch test.txt`
        `git add test.txt`
        `git commit -m 'test'`
        commit = `git rev-parse HEAD`.chomp
      end

      # require the new commit
      pod = LocalPod.new(fixture_spec('banana-lib/BananaLib.podspec'), temporary_sandbox, Platform.ios)
      pod.top_specification.stubs(:source).returns(
        :git => tmp_repo_path, :commit => commit
      )
      downloader = Downloader.for_pod(pod)
      downloader.download
      (pod.root + 'test.txt').should.exist?
    end

    it "doesn't update the cache if the ref is available" do
      @pod.top_specification.stubs(:source).returns(
        :git => fixture('banana-lib'), :commit => 'fd56054'
      )
      downloader = Downloader.for_pod(@pod)
      downloader.download
      @pod.root.rmtree
      downloader.expects(:update_cache).never
      downloader.download
    end

    it "updates the cache if the branch is not available" do
      # create the origin repo and the cache
      tmp_repo_path = temporary_directory + 'banana-lib-source'
      `git clone #{fixture('banana-lib')} #{tmp_repo_path}`

      @pod.top_specification.stubs(:source).returns(
        :git => tmp_repo_path, :branch => 'master'
      )
      downloader = Downloader.for_pod(@pod)
      downloader.download

      # make a new branch in the origin
      branch = 'test'
      Dir.chdir(tmp_repo_path) do
        `touch test.txt`
        `git checkout -b #{branch} >/dev/null 2>&1`
        `git add test.txt`
        `git commit -m 'test'`
      end

      # require the new branch
      pod = LocalPod.new(fixture_spec('banana-lib/BananaLib.podspec'), temporary_sandbox, Platform.ios)
      pod.top_specification.stubs(:source).returns(
        :git => tmp_repo_path, :branch => branch
      )
      downloader = Downloader.for_pod(pod)
      downloader.download
      (pod.root + 'test.txt').should.exist?
    end

    it "doesn't update the cache if the branch is available" do
      @pod.top_specification.stubs(:source).returns(
        :git => fixture('banana-lib'), :branch => 'master'
      )
      downloader = Downloader.for_pod(@pod)
      downloader.download
      @pod.root.rmtree
      downloader.expects(:update_cache).never
      downloader.download
    end
  end


  describe "for GitHub repositories, with :download_only set to true" do
    extend SpecHelper::TemporaryDirectory

    before do
      @pod = LocalPod.new(fixture_spec('banana-lib/BananaLib.podspec'), temporary_sandbox, Platform.ios)
    end

    it "downloads HEAD with no other options specified" do
      @pod.top_specification.stubs(:source).returns(
        :git => "git://github.com/lukeredpath/libPusher.git", :download_only => true
      )
      downloader = Downloader.for_pod(@pod)

      VCR.use_cassette('tarballs', :record => :new_episodes) { downloader.download }

      # deliberately keep this assertion as loose as possible for now
      (@pod.root + 'README.md').readlines[0].should =~ /libPusher/
    end

    it "downloads a specific tag when specified" do
      @pod.top_specification.stubs(:source).returns(
        :git => "git://github.com/lukeredpath/libPusher.git", :tag => 'v1.1', :download_only => true
      )
      downloader = Downloader.for_pod(@pod)

      VCR.use_cassette('tarballs', :record => :new_episodes) { downloader.download }

      # deliberately keep this assertion as loose as possible for now
      (@pod.root + 'libPusher.podspec').readlines.grep(/1.1/).should.not.be.empty
    end

    it "downloads a specific branch when specified" do
      @pod.top_specification.stubs(:source).returns(
        :git => "git://github.com/lukeredpath/libPusher.git", :branch => 'gh-pages', :download_only => true
      )
      downloader = Downloader.for_pod(@pod)

      VCR.use_cassette('tarballs', :record => :new_episodes) { downloader.download }


      # deliberately keep this assertion as loose as possible for now
      (@pod.root + 'index.html').readlines.grep(/libPusher Documentation/).should.not.be.empty
    end

    it "downloads a specific commit when specified" do
      @pod.top_specification.stubs(:source).returns(
        :git => "git://github.com/lukeredpath/libPusher.git", :commit => 'eca89998d5', :download_only => true
      )
      downloader = Downloader.for_pod(@pod)

      VCR.use_cassette('tarballs', :record => :new_episodes) { downloader.download }

      # deliberately keep this assertion as loose as possible for now
      (@pod.root + 'README.md').readlines[0].should =~ /PusherTouch/
    end
  end
end

