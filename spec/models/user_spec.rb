require 'rails_helper'

describe User do

  before(:all) { WebMock.disable! }
  after(:all) { WebMock.disable! }

  let(:user) { User.create!({ :email => "ben@example.com" }) }
  let(:user_2) { User.create!({ :invite_count => 1, :email => "bob@example.com" }) }

  describe "replications" do
    let!('replication_1') do
      Replication.create(
        replicating_study_id: 0,
        study_id: 1,
        closeness: 2,
        owner_id: user.id
      )
    end
    let!('replication_2') do
      Replication.create(
        replicating_study_id: 3,
        study_id: 1,
        closeness: 4,
        owner_id: user.id
      )
    end
    let!('replication_3') do
      Replication.create(
        replicating_study_id: 3,
        study_id: 1,
        closeness: 4,
        owner_id: user_2.id
      )
    end

    it "allows all replications created by a user to be looked up" do
      user.replications.count.should == 2
    end
  end

  describe "articles" do
    let!(:article) { Article.create(doi: '123banana', title: 'hello world', owner_id: user.id) }
    let!(:article_2) { Article.create(doi: '123apple', title: 'awesome man', owner_id: user.id) }
    let!(:article_3) { Article.create(doi: '123apple', title: 'awesome man', owner_id: user_2.id) }

    it "allows all articles created by a user to be looked up" do
      user.articles.count.should == 2
    end
  end

  describe "studies" do
    let!(:s1) { Study.create( article_id: 0, owner_id: user.id) }
    let!(:s2) { Study.create( article_id: 0, owner_id: user.id) }
    let!(:s3) { Study.create( article_id: 0, owner_id: user_2.id) }

    it "allows all studies created by a user to be looked up" do
      user.studies.count.should == 2
    end
  end

  describe "findings" do
    let!(:s1) { Study.create( article_id: 0, owner_id: user.id) }
    let!(:f1) { s1.findings.create(url: 'www.example.com', name: 'finding.txt', owner_id: user.id) }
    let!(:f2) { s1.findings.create(url: 'www.example2.com', name: 'finding2.txt', owner_id: user.id) }
    let!(:f3) { s1.findings.create(url: 'www.example3.com', name: 'finding3.txt', owner_id: user_2.id) }

    it "allows all findings created by a user to be looked up" do
      user.findings.count.should == 2
    end
  end

  describe "send_invite" do
    it "does not allow a user to send invites if invite_count is 0" do
      Invite.any_instance.should_not_receive(:send_invite)
      expect { user.send_invite('ben@example.com') }
        .to raise_error(Exceptions::NoInvitesAvailable)
    end

    it "allows an invite to be sent if invite_cout > 0" do
      Invite.any_instance.should_receive(:send_invite)
      user_2.invite_count.should == 1
      user_2.send_invite('ben@example.com')
      user_2.invite_count.should == 0
    end
  end

  describe "create_with_omniauth" do
    it "does not allow an account to be created if user not in invites table" do
      expect do
        User.create_with_omniauth(
          OpenStruct.new({
            info: OpenStruct.new({ email: 'foo@example.com', name: 'Ben' }),
            provider: 'fake-provider',
            uid: 'fake-uid'
          })
        )
      end.to raise_error(Exceptions::NotOnInviteList)
    end

    it "allows user on invite list to create an account" do
      Invite.create(email: 'foo@example.com')

      User.create_with_omniauth(
        OpenStruct.new({
          info: OpenStruct.new({ email: 'foo@example.com', name: 'BDizzle' }),
          provider: 'fake-provider',
          uid: 'fake-uid'
        })
      )

      user = User.find_by_email('foo@example.com')
      user.name.should == 'BDizzle'
    end
  end

  describe ".bookmarks" do
    let(:article) { Article.create(doi: '123banana', title: 'hello world', owner_id: user.id) }

    it "allows a user to bookmark an article" do
      user.bookmarks.create!(:bookmarkable => article)
      user.reload
      user.bookmarks.count.should == 1
    end
  end

  describe ".comments" do
    let(:article) { Article.create(doi: '123banana', title: 'hello world', owner_id: user.id) }

    it "returns the comments that the user has created" do
      article.comments.create!(owner: user, comment: "Some user comment")
      user.comments.count.should == 1
      user.comments.first.comment.should == "Some user comment"
    end
  end

end
