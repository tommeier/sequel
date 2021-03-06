require File.join(File.dirname(File.expand_path(__FILE__)), "spec_helper")

describe "Sequel::Plugins::LazyAttributes" do
  before do
    @db = MockDatabase.new
    @db.meta_def(:schema){|*a| [[:id, {:type=>:integer}], [:name,{:type=>:string}]]}
    class ::LazyAttributesModel < Sequel::Model(@db[:la])
      plugin :lazy_attributes
      set_columns([:id, :name])
      meta_def(:columns){[:id, :name]}
      lazy_attributes :name
      meta_def(:columns){[:id]}
      ds = dataset
      def ds.fetch_rows(sql)
        execute(sql)
        select = @opts[:select]
        where = @opts[:where]
        block = @mod_block || proc{|s| s}
        if !where
          if select.include?(:name)
            yield(block[:id=>1, :name=>'1'])
            yield(block[:id=>2, :name=>'2'])
          else
            yield(:id=>1)
            yield(:id=>2)
          end
        else
          i = where.args.last
          Array(i).each do |x|
            if sql =~ /SELECT name FROM/
              yield(block[:name=>x.to_s])
            else
              yield(block[:id=>x, :name=>x.to_s])
            end
          end
        end
      end
    end
    @c = ::LazyAttributesModel
    @ds = LazyAttributesModel.dataset
    @db.reset
  end
  after do
    Object.send(:remove_const, :LazyAttributesModel)
  end
  
  it "should allowing adding additional lazy attributes via plugin :lazy_attributes" do
    @c.set_dataset(@ds.select(:id, :blah))
    @c.dataset.sql.should == 'SELECT id, blah FROM la'
    @c.plugin :lazy_attributes, :blah
    @c.dataset.opts[:select].should == [:id]
    @c.dataset.sql.should == 'SELECT id FROM la'
  end
  
  it "should allowing adding additional lazy attributes via lazy_attributes" do
    @c.set_dataset(@ds.select(:id, :blah))
    @c.dataset.sql.should == 'SELECT id, blah FROM la'
    @c.lazy_attributes :blah
    @c.dataset.opts[:select].should == [:id]
    @c.dataset.sql.should == 'SELECT id FROM la'
  end

  it "should remove the attributes given from the SELECT columns of the model's dataset" do
    @ds.opts[:select].should == [:id]
    @ds.sql.should == 'SELECT id FROM la'
  end

  it "should still typecast correctly in lazy loaded column setters" do
    m = @c.new
    m.name = 1
    m.name.should == '1'
  end

  it "should lazily load the attribute for a single model object if there is an active identity map" do
    @c.with_identity_map do
      m = @c.first
      m.values.should == {:id=>1}
      m.name.should == '1'
      m.values.should == {:id=>1, :name=>'1'}
      @db.sqls.should == ['SELECT id FROM la LIMIT 1', 'SELECT name FROM la WHERE (id = 1) LIMIT 1']
    end
  end

  it "should lazily load the attribute for a single model object if there is no active identity map" do
    m = @c.first
    m.values.should == {:id=>1}
    m.name.should == '1'
    m.values.should == {:id=>1, :name=>'1'}
    @db.sqls.should == ['SELECT id FROM la LIMIT 1', 'SELECT name FROM la WHERE (id = 1) LIMIT 1']
  end

  it "should not lazily load the attribute for a single model object if the value already exists" do
    @c.with_identity_map do
      m = @c.first
      m.values.should == {:id=>1}
      m[:name] = '1'
      m.name.should == '1'
      m.values.should == {:id=>1, :name=>'1'}
      @db.sqls.should == ['SELECT id FROM la LIMIT 1']
    end
  end

  it "should not lazily load the attribute for a single model object if it is a new record" do
    @c.with_identity_map do
      m = @c.new
      m.values.should == {}
      m.name.should == nil
      @db.sqls.should == []
    end
  end

  it "should eagerly load the attribute for all model objects reteived with it" do
    @c.with_identity_map do
      ms = @c.all
      ms.map{|m| m.values}.should == [{:id=>1}, {:id=>2}]
      ms.map{|m| m.name}.should == %w'1 2'
      ms.map{|m| m.values}.should == [{:id=>1, :name=>'1'}, {:id=>2, :name=>'2'}]
      @db.sqls.should == ['SELECT id FROM la', 'SELECT id, name FROM la WHERE (id IN (1, 2))']
    end
  end

  it "should add the accessors to a module included in the class, so they can be easily overridden" do
    @c.class_eval do
      def name
        "#{super}-blah"
      end
    end
    @c.with_identity_map do
      ms = @c.all
      ms.map{|m| m.values}.should == [{:id=>1}, {:id=>2}]
      ms.map{|m| m.name}.should == %w'1-blah 2-blah'
      ms.map{|m| m.values}.should == [{:id=>1, :name=>'1'}, {:id=>2, :name=>'2'}]
      @db.sqls.should == ['SELECT id FROM la', 'SELECT id, name FROM la WHERE (id IN (1, 2))']
    end
  end

  it "should work with the serialization plugin" do
    @c.plugin :serialization, :yaml, :name
    @ds.instance_variable_set(:@mod_block, proc{|s| s.merge(:name=>"--- #{s[:name].to_i*3}\n")})
    @c.with_identity_map do
      ms = @ds.all
      ms.map{|m| m.values}.should == [{:id=>1}, {:id=>2}]
      ms.map{|m| m.name}.should == [3,6]
      ms.map{|m| m.values}.should == [{:id=>1, :name=>"--- 3\n"}, {:id=>2, :name=>"--- 6\n"}]
      ms.map{|m| m.deserialized_values}.should == [{:name=>3}, {:name=>6}]
      ms.map{|m| m.name}.should == [3,6]
      @db.sqls.should == ['SELECT id FROM la', 'SELECT id, name FROM la WHERE (id IN (1, 2))']
    end
    @db.reset
    @c.with_identity_map do
      m = @ds.first
      m.values.should == {:id=>1}
      m.name.should == 3
      m.values.should == {:id=>1, :name=>"--- 3\n"}
      m.deserialized_values.should == {:name=>3}
      m.name.should == 3
      @db.sqls.should == ["SELECT id FROM la LIMIT 1", "SELECT name FROM la WHERE (id = 1) LIMIT 1"]
    end
  end
end
