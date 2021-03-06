require 'rails_helper'

describe ArticlesController, :type => :controller do

  let(:user) { User.create!({ :email => "ben@example.com", :curator => true }) }
  let(:user_2) { User.create!({ :email => "christian@example.com" }) }

  let(:article) { Article.create!(doi: '123banana', title: 'hello world', owner_id: user.id, updated_at: '2006-03-05') }
  let(:article_2) { Article.create!(doi: '123apple', title: 'awesome article', owner_id: user_2.id, updated_at: '2007-03-05') }
  let(:article_3) { Article.create!(doi: '123mango', title: 'article 3', owner_id: user.id, updated_at: '2008-03-05') }
  let(:article_4) { Article.create!(doi: '123pear', title: 'article 4', owner_id: user_2.id, updated_at: '2010-03-05') }
  let(:article_5) { Article.create!(doi: '123guava', title: 'article 5', owner_id: user.id, updated_at: '2010-04-05') }
  let(:article_6) { Article.create!(doi: '123peach', title: 'article 6', owner_id: user_2.id, updated_at: '2010-04-06') }

  let(:author) {
    author = Author.create!({first_name: 'cat', last_name: 'dog'})
    author.articles << article_5
    author.articles << article_6
    author.save
    author
  }

  let(:author_2) { Author.create!({first_name: 'rabbit', last_name: 'dog'}) }
  let(:author_3) { Author.create!({first_name: 'horse', last_name: 'dog'}) }

  before(:all) do
    WebMock.disable!
    Timecop.freeze(Time.local(1990))
  end
  after(:all) do
    WebMock.enable!
    Timecop.return
  end
  before(:each) do
    # reset ES index, and make sure
    # testing articles are indexed.
    reset_index
    Article.put_mapping
    [article, article_2, article_3, article_4, article_5, article_6]
    ElasticMapper.index.refresh

    # fake :user being logged in
    controller.stub(:current_user).and_return(user)
  end

  describe "#index" do
    it "should return the list of articles" do
      get :index
      results = JSON.parse(response.body)
      results['documents'].count.should == 6
      results['total'].should == 6
    end

    it "returns a list articles for an author" do
      get :index, :author_id => author.id
      results = JSON.parse(response.body)
      results.count.should == 2
    end
  end

  describe "#show" do
    it "should return the article corresponding to the id" do
      get :show, id: article.id
      JSON.parse(response.body)['id'].should == article.id
    end

    it "should return a 404 if article not found" do
      get :show, id: -1
      response.status.should == 404
    end
  end

  describe "#recent" do
    it "should return the three most recent articles" do
      get :recent
      results = JSON.parse(response.body)
      results.length.should == 3
      results[2]['doi'].should == '123pear'
      results[1]['doi'].should == '123guava'
      results[0]['doi'].should == '123peach'

    end

  end

  describe "#create" do
    it "should return a 500 if title not provided" do
      post :create, { doi: 'abc123' }
      response.status.should == 500
      err = JSON.parse(response.body)
      err['messages']['title'].should == ["can't be blank"]
    end

    it "should allow an article to be created with DOI and title" do
      post :create, { title: 'my awesome title', doi: 'abc555' }
      article = JSON.parse(response.body)
      article['publication_date'].should == '1990-01-01'

      # we should have already indexed article in ES,
      # and be able to grab it.
      get :index
      results = JSON.parse(response.body)

      results['documents'].count.should == 7
      results['total'].should == 7
    end

    it "should allow publication_date to be set when creating an article" do
      # publication date is in format year-month-day,
      # the problem with a timestamp is that if the user
      # is in a country in a different time-zone,
      # publication_date could be off by a day.
      post :create, {
        title: 'my awesome title',
        doi: 'abc555',
        publication_date: '2006-3-5'
      }
      article = JSON.parse(response.body)
      article['publication_date'].should == '2006-03-05'
    end

    it "should allow tags to be set when creating an article" do
      post :create, { title: 'my awesome title', doi: 'abc555', tags: ["apple", "bat"] }
      article = JSON.parse(response.body)
      article['tags'].should == ["apple", "bat"]
    end

    it "should allow authors to be set when creating an article" do
      post :create, {
        title: 'my new awesome title',
        doi: '111111',
        authors: [{id: author.id}]
      }
      article = Article.find_by_doi('111111')
      article.authors.should include(author)
    end

    it "should set the owner when creating an article" do
      post :create, { title: 'my awesome title', doi: 'abc555' }
      article = Article.find_by_doi('abc555')
      article.owner.should == user
    end

    it "should order authors" do
      post :create, {
        title: 'my new awesome title',
        doi: '111111',
        authors: [{id: author.id}, {id: author_3.id}, {id: author_2.id}]
      }
      # results = JSON.parse(response.body)
      # results["authors"].map{|res_author| res_author["id"]}.should == [author.id, author_3.id, author_2.id]
      article = Article.find_by_doi('111111')
      article.authors.should == [author, author_3, author_2]

      ArticleAuthor.find_by(:article_id => article.id, :author_id => author.id).number.should == 0
      ArticleAuthor.find_by(:article_id => article.id, :author_id => author_2.id).number.should == 2
      ArticleAuthor.find_by(:article_id => article.id, :author_id => author_3.id).number.should == 1
    end

    it "should log changes to model_updates" do
      post :create, { title: 'my awesome title', doi: 'abc555' }
      article = Article.find_by_doi('abc555')
      article.model_updates.count.should == 1
      article.model_updates.first.operation.should == "model_created"
    end
    it "should save new authors" do
      post :find_doi, {
        doi: "10.1177/1948550612448196"
      }
      results = JSON.parse(response.body)  
      authors = results['authors']
      doi = results['doi']
      title = results['title']
      authors.count.should == 2
      post :create, { 
        doi: doi,
        title: title,
        authors: authors
      }
      article = Article.find_by_doi('10.1177/1948550612448196')
      article.authors.count.should == 2
      expect(article.authors[0]).not_to be_new_record  
    end 
  end

  describe '#update' do
    it "should raise a 404 if article not found" do
      post :update, { id: -1 }
      response.status.should == 404
    end

    it "should allow the title to be changed" do
      post :update, { id: article.id, title: "my new title" }
      article.reload
      article.title.should == 'my new title'
    end

    it "should allow the publication date to be changed" do
      post :update, { id: article.id, publication_date: "2014-3-3" }
      article.reload
      article.publication_date.should == Date.parse('2014-03-03')
    end

    it "should allow tags to be changed" do
      post :update, { id: article.id, tags: ["foo", "bar"] }
      article.reload
      article.tags.should == ["foo", "bar"]
    end

    it "should allow the authors to be changed" do
      post :update, {
        id: article.id,
        authors: [{id: author.id}]
      }
      article.reload
      article.authors.should include(author)
    end

    it "should allow the authors to be removed" do
      article.authors = [author]
      article.save

      post :update, {
        id: article.id,
        authors: []
      }
      article.reload
      article.authors.count.should == 0
    end

    it "should allow the authors to be removed when passed nil" do
      article.authors = [author]
      article.save

      post :update, {
        id: article.id,
        authors: nil
      }
      article.reload
      article.authors.count.should == 0
    end

    it "allows the doi to be removed if passed nil" do
      post :update, {
        id: article.id,
        doi: nil
      }
      article.reload
      article.doi.should be_nil
    end

    it "allows the doi to be removed if passed an empty string" do
      post :update, {
        id: article.id,
        doi: ""
      }
      article.reload
      article.doi.should be_nil
    end

    it "should allow the abstract to be changed" do
      post :update, { id: article.id, abstract: "my wacky research" }
      article.reload
      article.abstract.should == 'my wacky research'
    end

    it "should allow a curator to update any article" do
      post :update, { id: article_2.id, title: "my wacky research" }
      response.status.should == 200
      article_2.reload
      article_2.title.should == 'my wacky research'
    end

    it "should raise a 401 if non-curator tries to update article" do
      controller.stub(:current_user).and_return(user_2)
      post :update, { id: article_2.id, title: "my wacky research" }
      response.status.should == 401
      article_2.reload
      article_2.title.should == 'awesome article'
    end

    it "should log changes to model_updates" do
      post :update, { id: article.id, title: "my wacky research" }
      article.reload
      article.model_updates.count.should == 1
      article.model_updates.first.operation.should == "model_updated"
    end
  end

  describe "#find_doi" do
    it "should find article when doi correct" do
      post :find_doi, {
        doi: "10.1177/1948550612448196"
      }
      response.status.should == 200
      results = JSON.parse(response.body)
      results['journal_title'].should include("Social Psychological")
    end
    it "should return error when doi incorrect" do
      post :find_doi, {
        doi: "incorrect/doi"

      }
      response.status.should == 404
    end
    it "should return error when doi is blank" do
      post :find_doi, {
        doi: ""
      }
      response.status.should == 404
    end
    it "should not save authors when get metadata by doi" do
      post :find_doi, {
        doi: "10.1177/1948550612448196"
      }
      results = JSON.parse(response.body) 
      results['authors'][0]['id'].should == nil
      results['authors'][0]['last_name'].should == "LeBel"
    end
  end

  describe "#destroy" do
    it "allows an article created by current_user to be destroyed" do
      delete :destroy, { id: article.id }
      response.status.should == 204

      get :index
      results = JSON.parse(response.body)
      results['documents'].count.should == 5
      results['total'].should == 5
    end

    it "allows a curator to destroy any article" do
      delete :destroy, { id: article_2.id }
      response.status.should == 204

      get :index
      results = JSON.parse(response.body)
      results['documents'].count.should == 5
      results['total'].should == 5
    end

    it "does not allow a non-curator to destroy any article" do
      controller.stub(:current_user).and_return(user_2)
      delete :destroy, { id: article_2.id }
      response.status.should == 401

      get :index
      results = JSON.parse(response.body)
      results['documents'].count.should == 6
      results['total'].should == 6
    end


    it "returns a 404 if article is not found" do
      delete :destroy, { id: -1 }
      response.status.should == 404
    end
  end
end
