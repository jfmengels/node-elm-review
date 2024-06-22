export type StyledMessage = StyledMessagePart[];

export type StyledMessagePart = string | FormattedString;

export type FormattedString = {
  string: string;
  href?: string;
  color?: string;
};
