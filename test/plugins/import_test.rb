# Author:: Victor Costan
# Copyright:: Copyright (C) 2009 Zergling.Net
# License:: MIT

require 'zerg_xcode'
require 'test/unit'
require 'plugins/helper.rb'

require 'rubygems'
require 'flexmock/test_unit'

module Plugins; end

class Plugins::ImportTest < Test::Unit::TestCase
  include Plugins::TestHelper
  
  def setup
    super
    @plugin = ZergXcode.plugin 'import'
  end
  
  def test_import_identical_small
    project = ZergXcode.load 'test/fixtures/TestApp'
    assert_import_identical project
  end
  
  def test_import_identical_large
    project = ZergXcode.load 'test/fixtures/ZergSupport'
    assert_import_identical project    
  end

  def test_import_identical_30app
    project = ZergXcode.load 'test/fixtures/TestApp30'
    assert_import_identical project
  end
  
  def test_import_identical_30lib
    project = ZergXcode.load 'test/fixtures/TestApp30'
    assert_import_identical project
  end

  def test_import_differents
    small = ZergXcode.load 'test/fixtures/TestApp'
    large = ZergXcode.load 'test/fixtures/ZergSupport'
    assert_import_differents small, large
  end
  
  def test_import_differents_30
    small = ZergXcode.load 'test/fixtures/TestApp30'
    large = ZergXcode.load 'test/fixtures/TestLib30'
    assert_import_differents small, large    
  end

  def assert_import_differents(small, large)
    small_file_set = Set.new(small.all_files.map { |file| file[:path] })
    small_target_set = Set.new(small['targets'].map { |t| t['name'] })
    small_target_filesets = target_filesets small
    
    large_file_set = Set.new(large.all_files.map { |file| file[:path] })
    large_target_set = Set.new(large['targets'].map { |t| t['name'] })
    large_target_filesets = target_filesets large
    
    @plugin.import_project! large, small
    merged_files_set = Set.new(small.all_files.map { |file| file[:path] })
    merged_target_set = Set.new(small['targets'].map { |t| t['name'] })
    merged_target_filesets = target_filesets small
    
    assert_equal((small_file_set + large_file_set), merged_files_set,
                 "Files")
    assert_equal((small_target_set + large_target_set), merged_target_set,
                 "Targets")
    assert_equal small_target_filesets.merge(large_target_filesets),
                 merged_target_filesets, "Targets / files associations"
  end
  
  # Produces a map of target to file associations for a project.
  # 
  # Looks like this:
  # { 'target1' => Set(['filename1.m', 'filename2.h']) }
  def target_filesets(project)
    Hash[*(project['targets']).map { |target|
      [target['name'], Set.new(target.all_files.map { |f| f[:object]['path'] })]
    }.flatten]
  end

  
  # Clones a project, zaps its metadata, and then tries to merge the clone onto
  # the original. The result should be the original.
  def assert_import_identical(project)
    real_files = project.all_files.select { |f| f[:path][0, 1] == '.' }
    pre_archive = ZergXcode::Archiver.archive_to_hash project
    
    cloned_project = ZergXcode::XcodeObject.from project    
    cloned_project.visit_once do |object, parent, key, value|
      object.version = nil
      object.archive_id = nil
      next true
    end
    
    file_ops = @plugin.import_project! cloned_project, project
    post_archive = ZergXcode::Archiver.archive_to_hash project
    assert_equal pre_archive, post_archive
    
    assert_equal real_files.length, file_ops.length, 'File operations length'
  end
  
  def test_bin_mappings
    proj = ZergXcode.load 'test/fixtures/TestApp'
    mappings = @plugin.cross_reference proj, ZergXcode::XcodeObject.from(proj)
    
    bins = @plugin.bin_mappings mappings, proj
    merge, overwrite = bins[:merge], bins[:overwrite]
    
    assert_equal Set.new, merge.intersection(overwrite),
                 "Merge and overwrite sets should be disjoint"
    
    [proj['mainGroup'], proj['buildConfigurationList']].each do |object|    
      assert merge.include?(object), "#{object.xref_key.inspect} not in merge"
    end
    
    assert !merge.include?(proj), "Project should not be in any bin"
    assert !overwrite.include?(proj), "Project should not be in any bin"
  end
  
  def test_cross_reference_identical_small
    project = ZergXcode.load 'test/fixtures/TestApp'
    assert_cross_reference_covers_project project
  end
  
  def test_cross_reference_identical_large
    project = ZergXcode.load 'test/fixtures/ZergSupport'
    assert_cross_reference_covers_project project    
  end

  def test_cross_reference_identical_30app
    project = ZergXcode.load 'test/fixtures/TestApp30'
    assert_cross_reference_covers_project project
  end

  def test_cross_reference_identical_30lib
    project = ZergXcode.load 'test/fixtures/TestLib30'
    assert_cross_reference_covers_project project
  end
  
  def assert_cross_reference_covers_project(project)
    cloned_project = ZergXcode::XcodeObject.from project
    
    map = @plugin.cross_reference project, cloned_project
    objects = Set.new([cloned_project])
    cloned_project.visit_once do |object, parent, key, value|
      objects << value if value.kind_of? ZergXcode::XcodeObject
      true
    end
    
    objects.each do |object|
      assert map.include?(object),
             "Missed object #{object.xref_key.inspect}: #{object.inspect}"
      
      assert_equal object.xref_key, map[object].xref_key,
                   "Merge keys for cross-referenced objects do not match"
    end
  end
  
  def test_execute_file_ops
    ops = [{ :op => :delete, :path => 'test/fixtures/junk.m' },
           { :op => :copy, :from => 'test/awesome.m',
                           :to => 'test/fixtures/NewDir/awesome.m' },
           { :op => :copy, :from => 'test/ghost.m',
                           :to => 'test/fixtures/Dir/ghost.m' },
          ]
    flexmock(File).should_receive(:exist?).with('test/fixtures/junk.m').
                   and_return(true)
    flexmock(FileUtils).should_receive(:rm_r).with('test/fixtures/junk.m').
                        and_return(nil)
    flexmock(File).should_receive(:exist?).with('test/fixtures/NewDir').
                   and_return(false)
    flexmock(FileUtils).should_receive(:mkdir_p).with('test/fixtures/NewDir').
                        and_return(nil)
    flexmock(File).should_receive(:exist?).with('test/awesome.m').
                   and_return(true)
    flexmock(FileUtils).should_receive(:cp_r).
                        with('test/awesome.m',
                             'test/fixtures/NewDir/awesome.m').
                        and_return(nil)
    flexmock(File).should_receive(:exist?).with('test/fixtures/Dir').
                   and_return(true)
    flexmock(File).should_receive(:exist?).with('test/ghost.m').
                   and_return(false)

    output = capture_output { @plugin.execute_file_ops! ops }
    assert output.index('test/ghost.m'), "Output does not indicate copy failure"
  end
  
  def test_import_file_ops_flatten
    small = ZergXcode.load 'test/fixtures/TestApp'
    flat = ZergXcode.load 'test/fixtures/FlatTestApp'
    
    golden_ops = [
      ['delete', 'test/fixtures/TestApp/Classes/TestAppAppDelegate.h', '*'],
      ['delete', 'test/fixtures/TestApp/Classes/TestAppAppDelegate.m', '*'],
      ['delete', 'test/fixtures/TestApp/Classes/TestAppViewController.h', '*'],
      ['delete', 'test/fixtures/TestApp/Classes/TestAppViewController.m', '*'],
      ['copy', 'test/fixtures/TestApp/TestAppAppDelegate.h',
               'test/fixtures/FlatTestApp/TestAppAppDelegate.h'],
      ['copy', 'test/fixtures/TestApp/TestAppAppDelegate.m',
               'test/fixtures/FlatTestApp/TestAppAppDelegate.m'],
      ['copy', 'test/fixtures/TestApp/TestAppViewController.h',
               'test/fixtures/FlatTestApp/TestAppViewController.h'],
      ['copy', 'test/fixtures/TestApp/TestAppViewController.m',
               'test/fixtures/FlatTestApp/TestAppViewController.m'],
      ['copy', 'test/fixtures/TestApp/TestApp_Prefix.pch',
               'test/fixtures/FlatTestApp/TestApp_Prefix.pch'],
      ['copy', 'test/fixtures/TestApp/main.m',
               'test/fixtures/FlatTestApp/main.m'],
      ['copy', 'test/fixtures/TestApp/TestAppViewController.xib',
               'test/fixtures/FlatTestApp/TestAppViewController.xib'],
      ['copy', 'test/fixtures/TestApp/MainWindow.xib',
               'test/fixtures/FlatTestApp/MainWindow.xib'],
      ['copy', 'test/fixtures/TestApp/Info.plist',
               'test/fixtures/FlatTestApp/Info.plist'],
    ]
    
    
    file_ops = @plugin.import_project! flat, small
    flat_ops = file_ops.map do |op|
      [op[:op].to_s, op[:to] || op[:path], op[:from] || '*']
    end
    assert_equal golden_ops.sort, flat_ops.sort
  end
  
  def test_import_file_ops_branch
    small = ZergXcode.load 'test/fixtures/TestApp'
    flat = ZergXcode.load 'test/fixtures/FlatTestApp'
    
    golden_ops = [
      ['delete', 'test/fixtures/FlatTestApp/TestAppAppDelegate.h', '*'],
      ['delete', 'test/fixtures/FlatTestApp/TestAppAppDelegate.m', '*'],
      ['delete', 'test/fixtures/FlatTestApp/TestAppViewController.h', '*'],
      ['delete', 'test/fixtures/FlatTestApp/TestAppViewController.m', '*'],
      ['copy', 'test/fixtures/FlatTestApp/Classes/TestAppAppDelegate.h',
               'test/fixtures/TestApp/Classes/TestAppAppDelegate.h'],
      ['copy', 'test/fixtures/FlatTestApp/Classes/TestAppAppDelegate.m',
               'test/fixtures/TestApp/Classes/TestAppAppDelegate.m'],
      ['copy', 'test/fixtures/FlatTestApp/Classes/TestAppViewController.h',
               'test/fixtures/TestApp/Classes/TestAppViewController.h'],
      ['copy', 'test/fixtures/FlatTestApp/Classes/TestAppViewController.m',
               'test/fixtures/TestApp/Classes/TestAppViewController.m'],
      ['copy', 'test/fixtures/FlatTestApp/TestApp_Prefix.pch',
               'test/fixtures/TestApp/TestApp_Prefix.pch'],
      ['copy', 'test/fixtures/FlatTestApp/main.m',
               'test/fixtures/TestApp/main.m'],
      ['copy', 'test/fixtures/FlatTestApp/TestAppViewController.xib',
               'test/fixtures/TestApp/TestAppViewController.xib'],
      ['copy', 'test/fixtures/FlatTestApp/MainWindow.xib',
               'test/fixtures/TestApp/MainWindow.xib'],
      ['copy', 'test/fixtures/FlatTestApp/Info.plist',
               'test/fixtures/TestApp/Info.plist'],
    ]
    
    file_ops = @plugin.import_project! small, flat
    branch_ops = file_ops.map do |op|
      [op[:op].to_s, op[:to] || op[:path], op[:from] || '*']
    end
    assert_equal golden_ops.sort, branch_ops.sort
  end
end
