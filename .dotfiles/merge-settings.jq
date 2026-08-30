def stable_union($local; $remote):
  reduce $remote[] as $item
    ($local; if index($item) == null then . + [$item] else . end);

def merge_settings($local; $remote):
  if ($local | type) == "object" and ($remote | type) == "object" then
    reduce ((($local | keys_unsorted) + ($remote | keys_unsorted)) | unique[]) as $key
      ({};
       .[$key] = if ($local | has($key)) and ($remote | has($key)) then
                   merge_settings($local[$key]; $remote[$key])
                 elif $local | has($key) then
                   $local[$key]
                 else
                   $remote[$key]
                 end)
  elif ($local | type) == "array" and ($remote | type) == "array" then
    stable_union($local; $remote)
  elif $prefer == "local" then
    $local
  elif $prefer == "remote" then
    $remote
  else
    error("prefer must be local or remote")
  end;

if $prefer == "local" or $prefer == "remote" then
  . as $local | input as $remote | merge_settings($local; $remote)
else
  error("prefer must be local or remote")
end
