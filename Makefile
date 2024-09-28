ALL:
	@mkdir -p coverage
	@dart run coverage:test_with_coverage -b >coverage/log 2>&1 -- --no-color -j 1 || awk '/^Consider enabling the flag/{exit} {print}' coverage/log
	@dart run coverage:format_coverage -i coverage -o coverage/report.txt -c
