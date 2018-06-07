require "mysql2"
require File.expand_path(File.dirname(__FILE__) + "/base.rb")

class ImportScripts::OpenAtrium < ImportScripts::Base

  DB_HOST ||= ENV['DB_HOST'] || "mariadb"
  DB_NAME ||= ENV['DB_NAME'] || "openatrium_austria"
  DB_PW ||= ENV['DB_PW'] || "secret"
  DB_USER ||= ENV['DB_USER'] || "openatrium"
  OA_FILES_DIR ||= ENV['OA_FILES_DIR'] || "/openatrium"

  puts "#{DB_USER}:#{DB_PW}@#{DB_HOST} wants #{DB_NAME}"

  def initialize
    super

    @client = Mysql2::Client.new(
      host: DB_HOST,
      username: DB_USER,
      password: DB_PW,
      database: DB_NAME
    )
  end

  def get_site_settings_for_import
    settings = super

    max_file_size = @client.query("SELECT max(filesize) size FROM files").first['size']
    max_file_size_kb = max_file_size / 1000 + 1

    settings[:max_image_size_kb] = [max_file_size_kb, SiteSetting.max_image_size_kb].max
    settings[:max_attachment_size_kb] = [max_file_size_kb, SiteSetting.max_attachment_size_kb].max

    settings
  end

  def execute
    import_users
    import_categories
    import_category_users
    import_first_node_revision
    import_remaining_node_revision
    import_comments
  end

  def import_users
    puts '', 'importing users'

    create_users(@client.query("SELECT u.uid id, u.pass pass, u.name username, u.mail email, u.created created, u.access access, n.title name, COALESCE(pv.value, p.field_profile_organization_value) foodcoop, p.field_profile_telephone_value phone, p.field_profile_url_value url FROM users u LEFT JOIN profile_values pv ON pv.uid = u.uid LEFT JOIN node n ON n.type = 'profile' AND n.uid = u.uid LEFT JOIN content_type_profile p ON p.nid = n.nid WHERE u.uid = 0 OR u.status = 1")) do |row|
      {id: row['id'], password: row['pass'], name: row['name'], username: row['username'], email: row['email'], website: row['url'], created_at: Time.zone.at(row['created']), last_seen_at: Time.zone.at(row['access']), custom_fields: {user_field_1: row['foodcoop'], user_field_2: row['phone']} }
    end
  end

  def import_categories
    puts '', 'importing categories'

    create_categories(@client.query("SELECT n.nid id, n.title name, o.og_description description, n.created created, n.changed changed FROM node n, og o WHERE n.type ='group' AND n.nid=o.nid")) do |row|
      {id: "#{row['id']}", name: row['name'], description: row['description'],  created_at: Time.zone.at(row['created']), updated_at: Time.zone.at(row['changed'])}
    end

    puts '', 'importing wiki categories'

    create_categories(@client.query("SELECT n.nid id, n.title name, o.og_description description, n.created created, n.changed changed FROM node n, og o WHERE n.type ='group' AND n.nid=o.nid")) do |row|
      pcid = category_id_from_imported_category_id("#{row['id']}")
      {id: "#{row['id']}_wiki", parent_category_id: pcid, all_topics_wiki: true, name: 'Wiki', description: "Wiki (#{row['name']})",  created_at: Time.zone.at(row['created']), updated_at: Time.zone.at(row['changed'])}
    end
  end

  def import_category_users
    puts '', 'setting notification level for categories'

    results = @client.query("SELECT nid, uid FROM og_uid", cache_rows: false)

    current = 0
    results.each do |row|
      user_id = user_id_from_imported_user_id(row['uid'])
      category_id = category_id_from_imported_category_id("#{row['nid']}")

      if user_id && category_id
        user = User.find(user_id)
        level = NotificationLevels.all[:watching]
        CategoryUser.set_notification_level_for_category(user, level, category_id)
      end

      current += 1
      print_status current, results.size
    end
  end

  def import_first_node_revision
    puts '', 'creating first post revision'

    results = @client.query("
          SELECT n.nid nid, n.type, MIN(nr.vid) vid, oa.group_nid category,
                 n.uid uid, nr.title title, nr.body body, n.created created,
                 COALESCE(t.tags, '') tags, COALESCE(u.cnt, 0) uploads,
                 cfd.field_date_value start_date, cfd.field_date_value end_date, cte.field_wo_value location
            FROM og_ancestry oa, node n, node_revisions nr
       LEFT JOIN (SELECT u.vid, COUNT(*) cnt FROM upload u GROUP BY u.vid) u
              ON nr.vid = u.vid
       LEFT JOIN (SELECT tn.vid, GROUP_CONCAT(DISTINCT td.name SEPARATOR ',') tags FROM term_node tn, term_data td WHERE tn.tid = td.tid GROUP BY tn.vid) t
              ON nr.vid = t.vid
       LEFT JOIN content_field_date cfd
              ON nr.nid = cfd.nid
             AND nr.vid = cfd.vid
       LEFT JOIN content_type_event cte
              ON nr.nid = cte.nid
             AND nr.vid = cte.vid
           WHERE n.type IN ('blog', 'book', 'event')
             AND n.nid = nr.nid
             AND n.nid = oa.nid
        GROUP BY nr.nid, oa.group_nid, nr.uid, nr.title, nr.body, nr.timestamp,
                 t.tags, u.cnt, cfd.field_date_value, cfd.field_date_value, cte.field_wo_value
        ", cache_rows: false)

    create_posts(results) do |row|
      {
        id: "nid:#{row['nid']}",
        title: row['title'].try(:strip),
        user_id: user_for_uid(row['uid']),
        category: category_id_from_imported_category_id("#{row['category']}#{row['type'] == 'book' ? '_wiki' : ''}"),
        raw: build_body(row),
        tags: row['tags'].split(','),
        created_at: Time.zone.at(row['created'])
      }
    end
  end

  def import_remaining_node_revision
    puts '', 'creating remaining post revision'

    results = @client.query("
          SELECT nr.nid nid, nr.vid, nr.log log,
                 nr.uid uid, nr.title title, nr.body body, nr.timestamp revised,
                 COALESCE(t.tags, '') tags, COALESCE(u.cnt, 0) uploads,
                 cfd.field_date_value start_date, cfd.field_date_value end_date, cte.field_wo_value location
            FROM og_ancestry oa, node n, node_revisions nr
       LEFT JOIN (SELECT u.vid, COUNT(*) cnt FROM upload u GROUP BY u.vid) u
              ON nr.vid = u.vid
       LEFT JOIN (SELECT tn.vid, GROUP_CONCAT(DISTINCT td.name SEPARATOR ',') tags FROM term_node tn, term_data td WHERE tn.tid = td.tid GROUP BY tn.vid) t
              ON nr.vid = t.vid
       LEFT JOIN content_field_date cfd
              ON nr.nid = cfd.nid
             AND nr.vid = cfd.vid
       LEFT JOIN content_type_event cte
              ON nr.nid = cte.nid
             AND nr.vid = cte.vid
           WHERE n.type IN ('blog', 'book', 'event')
             AND n.nid = nr.nid
             AND n.nid = oa.nid
             AND nr.vid NOT IN (SELECT MIN(vid) FROM node_revisions GROUP BY nid)
      ", cache_rows: false)

    current = 0
    results.each do |row|
      post = Post.find(post_id_from_imported_post_id("nid:#{row['nid']}"))
      user_id = user_id_from_imported_user_id(row['uid'])
      user = post.user
      user = User.find(user_id) if user_id

      PostRevisor.new(post).revise!(
        user,
        {
          title: row['title'].try(:strip),
          raw: build_body(row),
          tags: row['tags'].split(','),
          edit_reason: row['log']
        }, {
          bypass_bump: true,
          force_new_version: true,
          revised_at: Time.zone.at(row['revised'])
        })

      current += 1
      print_status current, results.size
    end
  end


  def import_comments
    puts '', 'creating replies in topics'

    total_count = @client.query("SELECT COUNT(*) count FROM comments").first['count']

    batch_size = 1000

    batches(batch_size) do |offset|
      results = @client.query("
          SELECT c.cid cid, c.pid pid, c.nid nid, c.uid uid, c.comment body, c.timestamp created,
                 COALESCE(u.cnt, 0) uploads
            FROM og_ancestry oa, comments c
       LEFT JOIN (SELECT cu.cid, COUNT(*) cnt FROM comment_upload cu GROUP BY cu.cid)  u
              ON u.cid = c.cid
           WHERE oa.nid = c.nid
        ORDER BY c.timestamp ASC
           LIMIT #{batch_size}
          OFFSET #{offset}
          ", cache_rows: false)

      break if results.size < 1

      next if all_records_exist? :posts, results.map { |p| "cid:#{p['cid']}" }

      create_posts(results, total: total_count, offset: offset) do |row|
        topic_mapping = topic_lookup_from_imported_post_id("nid:#{row['nid']}")
        if topic_mapping && topic_id = topic_mapping[:topic_id]
          h = {
            id: "cid:#{row['cid']}",
            topic_id: topic_id,
            user_id: user_for_uid(row['uid']),
            raw: add_cid_attachments_to_body(row['body'], row['uploads'], row['cid']),
            created_at: Time.zone.at(row['created']),
          }
          if row['pid']
            parent = topic_lookup_from_imported_post_id("cid:#{row['pid']}")
            h[:reply_to_post_number] = parent[:post_number] if parent && parent[:post_number] > (1)
          end
          h
        else
          puts "No topic found for comment #{row['cid']} @ #{row['nid']}"
          nil
        end
      end
    end
  end

  def add_query_attachments_to_body(body, cnt, query)
    return body unless cnt.to_i > 0

    body += "\n"

    results = @client.query(query)
    results.each do |row|
      filename = File.join(OA_FILES_DIR, row['filepath'])
      if !File.exists?(filename)
        puts "Attachment file doesn't exist: #{filename}"
        next
      end

      upload = create_upload(user_for_uid(row['uid']), filename, row['filename'])

      if upload.nil? || upload.sha1.nil? || !upload.valid?
        puts "Upload not valid :(  #{filename}"
        puts upload.errors.inspect if upload
        next
      end

      body += "\n" + attachment_html(upload, row['description'])
    end

    body
  end

  def add_cid_attachments_to_body(body, cnt, cid)
    add_query_attachments_to_body(body, cnt, "SELECT f.filename, f.filepath, f.uid, cu.description FROM files f, comment_upload cu WHERE f.fid = cu.fid AND cu.cid = #{cid} ORDER BY cu.weight")
  end

  def add_vid_attachments_to_body(body, cnt, vid)
    add_query_attachments_to_body(body, cnt, "SELECT f.filename, f.filepath, f.uid, u.description FROM files f, upload u WHERE f.fid = u.fid AND u.vid = #{vid} ORDER BY u.weight")
  end

  def build_body(row)
    body = add_vid_attachments_to_body(row['body'], row['uploads'], row['vid'])
    if row['type'] == 'event'
      str = "summary='#{row['title'].gsub('\'', '\\\'')}' dtstart='#{row['start_date']}' dtend='#{row['end_date']}'"
      str += " location='#{row['location'].gsub('\'', '\\\'')}'" if row['location']
      body = "[event #{str}][/event]\n\n#{body}"
    end
    body
  end

  def user_for_uid(uid)
    user_id_from_imported_user_id(uid) || user_id_from_imported_user_id(0) || Discourse::SYSTEM_USER_ID
  end

end

if __FILE__==$0
  ImportScripts::OpenAtrium.new.perform
end
