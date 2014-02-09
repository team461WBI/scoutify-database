class Match < ActiveRecord::Base
	require "net/http"
	include TBA

	has_many :records
	belongs_to :event

	def tba_update(key, teams_json = nil, matches_json = nil)
		unless matches_json
			res = tba_request :match, key

			tba_error(res.uri, res.code, res.body) unless res.is_a?(Net::HTTPSuccess)

			matches_json = MultiJson.load res.body
		end

		json = matches_json.detect{ |m| m["key"] = key }

		self.red_score  = json["alliances"]["red"]["score"]
		self.blue_score = json["alliances"]["blue"]["score"]
		self.number = json["key"].split("_")[1]
		self.save

		unless teams_json
			teams_res = tba_request :teams, json["team_keys"].join(",")

			tba_error(teams_res.uri, teams_res.code, teams_res.body) unless teams_res.is_a?(Net::HTTPSuccess)

			teams_json = MultiJson.load teams_res.body
		end

		["red", "blue"].each do |team_color|
			position_base_num = (team_color == "blue") ? 0 : 3
			
			json["alliances"][team_color]["teams"].map do |team_key|
				# Sometimes TBA uses team keys like "frc973B"; ignore these.
				if teams_json.detect { |t| t["key"] == team_key }
					team_number = (teams_json.detect { |t| t["key"] == team_key })["team_number"]
					team = Team.where(number: team_number).first
					
					unless team
						team = Team.create
						team.tba_update team_key
					end
				end
				
				query_string = "" # scope?
				
				if team_color == "red"
					query_string = "position < 3 AND team_id == ?"
				elsif team_color == "blue"
					query_string = "position >= 3 AND team_id == ?"
				end
				
				if records.where(query_string, (team && team.id)).empty?
					for i in position_base_num..(position_base_num + 2) do
						if records.where(position: i).empty?
							Record.create match_id: id, position: i, team_id: (team && team.id)
							break
						end
					end
				end
			end
		end
		self
	end
end
